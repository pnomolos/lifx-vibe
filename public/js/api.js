function Bulb() {
	var self = $.observable(this);
	var bulbs = {};
	
	self.add = function(bulb) {
		console.log("Adding bulb");
		bulbs[bulb.id] = bulb;
		self.trigger('add', bulb);
	}
}