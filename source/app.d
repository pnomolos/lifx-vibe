import lifx_gateway;

import vibe.vibe;

void index(HTTPServerRequest req, HTTPServerResponse res)
{
	render!("index.dt")(res);
}

void main()
{
	//auto gateway = new LIFXGateway();
	//gateway.GetLightState();

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	auto router = new URLRouter;
		router.get("/", serveStaticFile("./public/index.html"));
		router.get("*", serveStaticFiles("./public/"));
		router.get("*", serveStaticFile("./public/index.html"));
	
	listenHTTP(settings, router);
	lowerPrivileges();
	runEventLoop();
}
