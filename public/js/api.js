function Bulb() {
	var self = $.observable(this);
	var bulbs = {};
	
	self.add = function(bulb) {
		console.log("Adding bulb");
		replace = false;
		if (bulbs[bulb.id]) {
			replace = true;
		}
		bulbs[bulb.id] = bulb;
		self.trigger(replace ? 'replace' : 'add', bulb);
	}
}