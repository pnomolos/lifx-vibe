
/* The presenter */

var connection = null;

-function() { 'use strict';
	window.bulb = new Bulb();
	
	connection = new WebSocket('ws://localhost:8080/socket');
	
	// Log errors
	connection.onerror = function (error) {
		console.log('WebSocket Error ' + error);
	};
	
	connection.onopen = function () {
		console.log("Opening connection");
		connection.send('{"message": "get_light_state", "payload": null}');
	};
	
	connection.onmessage = function (e) {
		var resp = JSON.parse(e.data);
		console.log(resp);
		switch (resp.message) {
			case 'light_state':
				$.each(resp.params, function(){
					window.bulb.add(this);
				})
				break;
		}
	};
	
	var template = $("[type='html/bulb']").html(),
		root = $('#bulb-list');
	
	bulb
		.on("add", add)
		.on("replace", replace)
	;
	
	// Private
	function add(bulb) {
		console.log(bulb);
		var el = $($.render(template, bulb)).appendTo(root);
	}
	
	function replace(bulb) {
		var el = $('#' + bulb.id).replaceWith($.render(template, bulb));
	}
}()