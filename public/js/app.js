
/* The presenter */

-function() { 'use strict';
	window.bulb = new Bulb();
	
	var connection = new WebSocket('ws://localhost:8080/socket');
	
	// Log errors
	connection.onerror = function (error) {
		console.log('WebSocket Error ' + error);
	};
	
	console.log('here');

	// Log messages from the server
	connection.onmessage = function (e) {
		console.log('Server: ' + e.data);
		var resp = JSON.parse(e.data);
		console.log(resp);
	};
	
	var template = $("[type='html/bulb']").html(),
		root = $('#bulb-list');
		
	connection.onopen = function () {
		console.log("Opening connection");
		connection.send('Ping'); // Send the message 'Ping' to the server
	};
}()