LIFX.Router.map(function() {
	this.route("lifx", { path: "/" })
	this.resource('bulbs', {path: 'bulbs'});
	this.resource('bulb', {path: 'bulbs/:bulb_id'})
})

LIFX.IndexRoute = Ember.Route.extend({
	renderTemplate: function() {
		this.render('bulbs', {
			into: 'bulbs'
		})
	}
})

LIFX.BulbsRoute = Ember.Route.extend({
	setupController: function(controller) {
		controller.set('model', this.store.get('bulbs'));
	}
})

LIFX.BulbsController = Ember.ArrayController.extend();
LIFX.BulbController = Ember.ObjectController.extend();