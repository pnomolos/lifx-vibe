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
		while (socket.connected)
		{
			auto msg = socket.receiveText();
			writeln("Got: " ~ msg);

			// TODO: switch(type), etc.
			socket.send(encode_packet("light_state", m_gateway.get_light_state()));
			//writeln(encode_packet("light_state", m_gateway.get_light_state()));
		}
	}

	private LIFXGateway m_gateway;
}
