<<<<<<< HEAD
import std.stdio;
import lifx_gateway;
import vibe.vibe;

void main()
{
	//auto gateway = new LIFXGateway();

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	auto router = new URLRouter;
		router.get("/socket", handleWebSockets(&handleConn));
		router.get("/", serveStaticFile("./public/index.html"));
		router.get("*", serveStaticFiles("./public/"));
		router.get("*", serveStaticFile("./public/index.html"));
	
	listenHTTP(settings, router);
	lowerPrivileges();
	runEventLoop();
}

void handleConn(WebSocket sock)
{
	// simple echo server
	while(sock.connected){
		auto msg = sock.receiveText();
		writeln("Got: " ~ msg);
		sock.send("{\"msg\": \"" ~ msg ~ "\"}");
	}
}