
/* The presenter */

var connection = null;

-function() { 'use strict';
	connection = new WebSocket('ws://10.0.0.100:8080/socket');
	
	window.bulb = new Bulb(connection);
	
	var template = $("[type='html/bulb']").html(),
		root = $('#bulb-list');
	
	$(document).on('click', '.power', function() {
		bulb.toggle_power($(this).parents('.bulb').attr('id'));
	})
	
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