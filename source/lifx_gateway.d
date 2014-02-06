module lifx_gateway;

import std.stdio;
import std.c.string; // memcpy
import std.socket;
import std.bitmanip;
import std.format;

import vibe.vibe;
import vibe.core.connectionpool;

// Lifx protocol based on reverse engineered documentation from:
//   https://github.com/magicmonkey/lifxjs/blob/master/Protocol.md

private immutable k_udp_discovery_port = 56700;
private immutable k_packet_buffer_size = 1024;

private alias ubyte[6] BulbAddress;

// All the LIFX stuff is tightly packed w/o padding
align(1)
{
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

	private struct LightStatus
	{
		align(1):
		ushort hue;
		ushort saturation;
		ushort brightness;
		ushort kelvin;
		ushort dim;
		ushort power;
		char bulb_label[32]; // UTF-8 encoded string
		ulong tags;
	}
	static assert(LightStatus.sizeof == 52);
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

// Hacky way until we can do this properly!
private static auto connect_tcp_address(NetworkAddress address)
{
	string host = std.socket.InternetAddress.addrToString(swapEndian(address.sockAddrInet4().sin_addr.s_addr));
	return connectTCP(host, address.port);
}


// Handles sending and receiving packets over a single TCP connection to the LIFX
// gateway (i.e. can send to any of the bulbs).
// Used with a connection pool to avoid mixing communication from different clients.
private class LIFXConnection
{
	public this(UDPConnection connection, NetworkAddress address, BulbAddress gateway_address)
	{
		m_read_packet_header_valid = false;
		m_address = address;
		m_gateway_address = gateway_address;
		m_connection = connection;
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

		//m_connection.write(payload);
		m_connection.send(payload, &m_address);
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
			/*
			ubyte[PacketHeader.sizeof] buffer;
			m_connection.read(buffer);
			*/

			auto buffer = m_connection.recv(m_read_packet_buffer);

			m_read_packet_header = decode_header(buffer);
			m_read_packet_header_valid = true;

			// Some basic consistency checks...
			//enforce(m_read_packet_header.size >= PacketHeader.sizeof, "Invalid packet size");
			enforce(m_read_packet_header.size == buffer.length, "Invalid packet size");
		}

		return m_read_packet_header;
	}

	public const(ubyte)[] receive_packet_payload()
	{
		peek_packet_header();
		size_t payload_length = m_read_packet_header.size - PacketHeader.sizeof;

		//auto read_buffer = new ubyte[payload_length];
		//m_connection.read(read_buffer);
		auto read_buffer = m_read_packet_buffer[PacketHeader.sizeof .. m_read_packet_header.size];

		// Indicate that we're ready to move on to the next packet
		m_read_packet_header_valid = false;
		return read_buffer;
	}

	public void receive_packet(T...)(PacketType type, ref T packets)
	{
		PacketHeader header = peek_packet_header();
		if (type != header.packet_type)
			throw new Exception("Received unexpected packet type " ~ to!string(header.packet_type));

		decode_payload(receive_packet_payload(), packets);
	}


	private BulbAddress m_gateway_address;
	//private TCPConnection m_connection;

	private NetworkAddress m_address;
	private UDPConnection m_connection;

	private PacketHeader m_read_packet_header;
	private bool m_read_packet_header_valid;
	private ubyte[k_packet_buffer_size] m_read_packet_buffer;
}


// Minimal shadow state for bulbs
private class LIFXBulb
{
	public this(BulbAddress address)
	{
		this.address = address;

		// Just use a hex concatenation of the address as our stringified "label"
		auto writer = appender!string();
		formattedWrite(writer, "%X%X%X%X%X%X", address[0], address[1], address[2], address[3], address[4], address[5]);
		id = writer.data;
	}

	public immutable BulbAddress address;

	public string id;
	public string label;
	public bool power;
}


public class LIFXGateway
{
	public this()
	{
		// Bulb discovery is done by sending a UDP broadcast and listening for a reply
		// TODO: Fix broadcast address for local subnet
		auto broadcast_address = resolveHost("255.255.255.255");
		broadcast_address.port = k_udp_discovery_port;
		
		auto udp = listenUDP(k_udp_discovery_port, "0.0.0.0");
		udp.canBroadcast(true);
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

				if (response.service == GatewayService.UDP)
				{
					// Looks good, we'll use it!
					gateway_network_address.port = cast(ushort)response.port;
					gateway_address = header.gateway_address;
					writeln("Found gateway, address:", gateway_address);
					break;
				}
			}
		}

		m_connection = new LIFXConnection(udp, gateway_network_address, gateway_address);

		// We spawn one initial connection/fiber to keep track of light state even if no
		// client fibers are active.
		runTask(&light_receive_task);
	}

	private void light_receive_task()
	{
		// TODO: Enumerate bulbs (on some timeout... waitForData?) and create LIFXBulb wrappers for them
		m_connection.send_packet(PacketType.get_light_state);
		
		for (;;)
		{
			// TODO: Timeout/wait for data and send a new get_light_state if hit
			auto header = m_connection.peek_packet_header();
			writefln("Received type %s!", header.packet_type);
			
			switch (header.packet_type)
			{
				case PacketType.light_state:
					// New light?
					// Test: Turn it off!
					//

					LightStatus status;
					m_connection.receive_packet(PacketType.light_state, status);

					// Find or create bulb wrapper
					auto bulbs = find!"a.address == b"(m_bulbs, header.target_address);
					if (bulbs.empty)
					{
						m_bulbs = m_bulbs ~ new LIFXBulb(header.target_address);
						bulbs = m_bulbs[$-1..$];
					}					
					assert(bulbs.length > 0);
					auto bulb = bulbs.ptr; // First element

					// Update state
					bulb.power = (status.power != 0);
					bulb.label = status.bulb_label[0 .. strlen(status.bulb_label.ptr)].idup;

					writefln("Bulb %s power %s from %s", bulb.id, bulb.power, status.power);

					break;

				case PacketType.power_state:
					// Just get it to send the whole state back
					m_connection.send_packet(PacketType.get_light_state, header.target_address);
					m_connection.receive_packet_payload(); // Discard payload
					break;

				default:
					writefln("Unhandled packet type %s!", header.packet_type);
					m_connection.receive_packet_payload(); // Discard
					break;
			}

			// TODO: Trigger broadcast new state to clients
			// Probably okay to always do this whenever we process a new packet, regardless of if it has changed
		}
	}

	// TODO: This is undesirable long-term... figure out a better way to handle id vs address
	public void toggle_power(string id)
	{
		auto bulbs = find!"a.id == b"(m_bulbs, id);
		if (!bulbs.empty)
			m_connection.send_packet(PacketType.set_power_state, bulbs[0].address, bulbs[0].power ? PowerState.OFF : PowerState.ON);
	}

	public Json get_light_state()
	{
		// For now, just return a copy of the shadowed state
		return serializeToJson(m_bulbs);
	}

	public ~this()
	{
		//	TODO: Stop listening?
	}

	private LIFXConnection m_connection;

	// All the bulbs we've seen so far, indexed by address
	private LIFXBulb[] m_bulbs;
}
