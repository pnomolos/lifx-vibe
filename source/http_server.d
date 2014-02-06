module http_server;

import std.stdio;
import lifx_gateway;
import vibe.vibe;

class HTTPServer
{
	public this()
	{
		m_gateway = new LIFXGateway();

		auto settings = new HTTPServerSettings;
		settings.port = 8080;

		auto router = new URLRouter;
		router.get("/socket", handleWebSockets(&handleConn));
		router.get("/", serveStaticFile("./public/index.html"));
		router.get("*", serveStaticFiles("./public/"));
		router.get("*", serveStaticFile("./public/index.html"));

		listenHTTP(settings, router);
	}

	private string encode_packet(string type, Json params = null)
	{
		Json result = Json.emptyObject;
		result.message = type;
		result.params = params;
		return serializeToJson(result).toString();
	}

	private void handleConn(WebSocket socket)
	{
		// TODO: Register ourselves for the various broadcasts
		// Perhaps means we should break out as a separate object too, we'll see

		while (socket.connected)
		{
			auto packet_string = socket.receiveText();
			//writeln("Got: " ~ packet_string);
			auto packet = parseJsonString(packet_string);

			// TODO: We could do some sort of hashed dispatch to delegates... MEH for now
			if (packet.message == "get_light_state")
			{
				socket.send(encode_packet("light_state", m_gateway.get_light_state()));	
			}
			else if (packet.message == "toggle_power")
			{
				m_gateway.toggle_power(packet.params["id"].get!string);
			}
		}
	}

	private LIFXGateway m_gateway;
}
