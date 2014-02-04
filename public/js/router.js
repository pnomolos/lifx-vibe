LIFX.Router.map(function() {
	// this.route("lifx", { path: "/" })
	this.resource('bulbs', {path: 'bulbs'});
	this.resource('bulb', {path: 'bulbs/:bulb_id'})
})

LIFX.IndexRoute = Ember.Route.extend({
	setupController: function(controller) {
		console.log(this.store.get('bulb'))
	},
	renderTemplate: function() {
		this.render('lifx')
	}
})

LIFX.BulbsRoute = Ember.Route.extend({});

LIFX.BulbsController = Ember.ArrayController.extend({
	content: function() {
		console.log('here');
		return this.store.findAll(LIFX.Bulb);
	}.property()
});
LIFX.BulbController = Ember.ObjectController.extend();