LIFX.Bulb = DS.Model.extend({
	id: DS.attr('string'),
	name: DS.attr('string')
});

LIFX.Bulb.FIXTURES = jQuery.get('/fixtures/bulbs.json');