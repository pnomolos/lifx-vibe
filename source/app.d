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
		router.get("/", &index);
		router.get("*", serveStaticFiles("./public/"));
	
	listenHTTP(settings, router);
	lowerPrivileges();
	runEventLoop();
}
