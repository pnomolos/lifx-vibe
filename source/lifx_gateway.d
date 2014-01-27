module lifx_gateway;

import std.stdio;
import std.c.string; // memcpy

import vibe.vibe;
import vibe.core.connectionpool;

version(Windows) import std.c.windows.winsock; // Some of the UDP/host resolution constants

// Lifx protocol based on reverse engineered documentation from:
//   https://github.com/magicmonkey/lifxjs/blob/master/Protocol.md

private immutable k_udp_discovery_port = 56700;

private immutable k_packet_buffer_size = 1024;

// All the LIFX stuff is tightly packed w/o padding
align(1)
{
	private alias ubyte[6] BulbAddress;

	private enum PacketType : ushort
	{
		get_pan_gateway = 0x02,
		pan_gateway = 0x03,

		get_light_state = 0x65,
		light_state = 0x6b,

		get_power_state = 0x14,
		set_power_state = 0x15,
		power_state = 0x16,
	}

	private struct PacketHeader
	{
		align (1):
		ushort size = PacketHeader.sizeof;
		ushort protocol = 13312;  // "Undefined?"
		uint reserved1 = 0;
		BulbAddress target_address;
		ushort reserved2 = 0;
		BulbAddress gateway_address;
		ushort reserved3 = 0;
		ulong timestamp = 0;
		PacketType packet_type;       // LE
		ushort reserved4 = 0;
	}
	static assert(PacketHeader.sizeof == 36);


	private enum GatewayService : byte
	{
		UDP = 1,
		TCP = 2,
	}
	private struct GatewayResponse
	{
		align(1):
		GatewayService service;
		uint port;     // LE
	}
	static assert(GatewayResponse.sizeof == 5);

	enum PowerState : ushort
	{
		OFF = 0,
		ON  = 1
	}
}

// TODO: Reconsider header union with new setup...
public pure ubyte[PacketHeader.sizeof] encode_header(T...)(PacketType type)
{
	PacketHeader header = PacketHeader.init;
	header.packet_type = type;
	ubyte[PacketHeader.sizeof] buffer;
	memcpy(buffer.ptr, &header, PacketHeader.sizeof);
	return buffer;
}

private const(PacketHeader) decode_header(const(ubyte)[] packet)
{
	PacketHeader header;
	assert(packet.length >= header.sizeof);
	memcpy(&header, packet.ptr, header.sizeof);
	return header;
}

private void decode_payload(T...)(const(ubyte)[] payload, ref T packets)
{
	foreach (ref p; packets)
	{
		alias typeof(p) p_type;
		assert(payload.length >= p.sizeof);
		memcpy(&p, payload.ptr, p.sizeof);
		// TODO: Endian conversion of p, if any
		payload = payload[p.sizeof .. $];
	}
}


// Handles sending and receiving packets over a single TCP connection to the LIFX
// gateway (i.e. can send to any of the bulbs).
// Used with a connection pool to avoid mixing communication from different clients.
private class LIFXConnection
{
	public this(string host, ushort port, BulbAddress gateway_address)
	{
		m_read_packet_header_valid = false;
		m_gateway_address = gateway_address;
		m_connection = connectTCP(host, port);
	}

	// TODO: Make some decisions about GC memory, etc.
	public void send_packet(T...)(PacketType type, BulbAddress target, in T packets)
	{
		ushort size = PacketHeader.sizeof;
		foreach (p; packets)
			size += p.sizeof;

		auto payload = new ubyte[size];
		size_t write_index = 0;	

		PacketHeader header = PacketHeader.init;
		header.packet_type = type;
		header.target_address = target;
		header.size = size;
		header.gateway_address = m_gateway_address;
		memcpy(payload.ptr + write_index, &header, header.sizeof);
		write_index += header.sizeof;

		foreach (p; packets)
		{
			alias typeof(p) p_type;
			// TODO: Endian conversion of p, if any
			memcpy(payload.ptr + write_index, &p, p.sizeof);
			write_index += p.sizeof;
		}

		m_connection.write(payload);
	}

	// Convenience
	public void send_packet(T...)(PacketType type)
	{
		send_packet(type, BulbAddress.init);
	}

	public const(PacketHeader) peek_packet_header()
	{
		if (!m_read_packet_header_valid)
		{
			ubyte[PacketHeader.sizeof] buffer;
			m_connection.read(buffer);
			m_read_packet_header = decode_header(buffer);
			m_read_packet_header_valid = true;

			// Some basic consistency checks...
			enforce(m_read_packet_header.size >= PacketHeader.sizeof, "Invalid packet size");
		}

		return m_read_packet_header;
	}

	public const(ubyte)[] receive_packet_payload()
	{
		peek_packet_header();
		size_t payload_length = m_read_packet_header.size - PacketHeader.sizeof;

		auto read_buffer = new ubyte[payload_length];
		m_connection.read(read_buffer);

		// Indicate that we're ready to move on to the next packet
		m_read_packet_header_valid = false;
		return read_buffer;
	}

	// TODO receive_packet utilizing decode_payload

	private BulbAddress m_gateway_address;
	private TCPConnection m_connection;

	private PacketHeader m_read_packet_header;
	private bool m_read_packet_header_valid;
}


// Minimal class that wraps actions being performed on a given bulb
// Try to minimize "shadow state"; the only purpose in this class is to
// track and kill outstanding script fibers that are talking to this bulb
// so as to avoid "fighting". i.e. when we receive a new "action", kill any
// ongoing actions first before executing it.
private class LIFXBulb
{
	public this(BulbAddress address, ConnectionPool!TCPConnection connection_pool)
	{
		m_address = address;
	}

	private immutable BulbAddress m_address;
	private ConnectionPool!LIFXConnection m_connection_pool;
}


public class LIFXGateway
{
	public this()
	{
		// Bulb discovery is done by sending a UDP broadcast and listening for a reply
		auto udp = listenUDP(k_udp_discovery_port, "0.0.0.0");
		udp.canBroadcast(true);

		// TODO: Fix broadcast address for local subnet
		auto broadcast_address = resolveHost("255.255.255.255", AF_UNSPEC, false);
		broadcast_address.port = k_udp_discovery_port;

		udp.send(encode_header(PacketType.get_pan_gateway), &broadcast_address);

		NetworkAddress gateway_network_address;
		BulbAddress gateway_address;
		for (;;)
		{
			ubyte[k_packet_buffer_size] buffer;
			auto packet = udp.recv(buffer, &gateway_network_address);
			auto header = decode_header(packet);

			writefln("Received type %d!", header.packet_type);

			// Check for a TCP gateway bulb
			if (header.packet_type == PacketType.pan_gateway)
			{
				GatewayResponse response;
				decode_payload(packet[PacketHeader.sizeof..$], response);

				if (response.service == GatewayService.TCP)
				{
					// Looks good, we'll use it!
					gateway_network_address.port = cast(ushort)response.port;
					gateway_address = header.gateway_address;
					writeln("Found gateway, address:", gateway_address);
					break;
				}
			}
		}
		
		m_connection_pool = new ConnectionPool!LIFXConnection({
			writeln("Added new connection to pool.");
			// NOTE: Connection address from discovery is disabled until we get a version
			// of connectTCP that works with NetworkAddresses (i.e. what we get back from the UDP query).
			// Hard-coded for now!
			return new LIFXConnection("10.0.0.205", gateway_network_address.port, gateway_address);
		});
	}

	void GetLightState()
	{
		auto connection = m_connection_pool.lockConnection();

		// TODO: Enumerate bulbs (on some timeout...?) and create LIFXBulb wrappers for them
		connection.send_packet(PacketType.get_light_state);
		for (;;)
		{
			auto header = connection.peek_packet_header();

			writefln("Received type %d!", header.packet_type);
			
			if (header.packet_type == PacketType.light_state)
			{
				// Test: Turn it off!
				connection.send_packet(PacketType.set_power_state, header.target_address, PowerState.OFF);
			}

			// Discard rest of the packet; TODO: Cleanup!
			connection.receive_packet_payload();
		}
	}

	public ~this()
	{
	}

	private ConnectionPool!LIFXConnection m_connection_pool;

	// All the bulbs we've seen so far, indexed by address
	private LIFXBulb[BulbAddress] m_bulbs;
}
