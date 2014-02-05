import std.stdio;
import http_server;
import vibe.vibe;

void main()
{
	auto server = new HTTPServer();

	lowerPrivileges();
	runEventLoop();
}
