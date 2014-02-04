import vibe.vibe;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	auto router = new URLRouter;
		router.get("/", handleWebSockets(&handleConn));
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
		if (msg == "abc") {
			sock.send(msg);
		}
	}
}