import vibe.vibe;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	listenHTTP(settings, &handleRequest);
	lowerPrivileges();
	runEventLoop();
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Hello, World!");
}