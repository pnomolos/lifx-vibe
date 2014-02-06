function Bulb(connection) {
	var connection = connection;
	
	// Log errors
	connection.onerror = function (error) {
		console.log('WebSocket Error ' + error);
	};
	
	connection.onopen = function () {
		console.log("Opening connection");
		self.init();
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
	
	
	var self = $.observable(this);
	var bulbs = {};
	
	self.init = function() {
		connection.send('{"message": "get_light_state", "params": null}');
	}
	
	self.add = function(bulb) {
		console.log("Adding bulb");
		replace = false;
		if (bulbs[bulb.id]) {
			replace = true;
		}
		bulb.power_state = bulb.power ? 'on' : 'off';
		bulbs[bulb.id] = bulb;
		self.trigger(replace ? 'replace' : 'add', bulb);
	}
	
	self.toggle_power = function(id) {
		connection.send('{"message": "toggle_power", "params": {"id": "' + id + '"}}');
		connection.send('{"message": "get_light_state", "payload": null}');
	}
}