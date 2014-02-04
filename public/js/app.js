window.LIFX = Ember.Application.create({
	Socket: EmberSockets.extend({
		host: 'localhost',
		port: 8080,
		path: 'socket',
		controllers: ['bulbs']
	}),
	
  // Basic logging, e.g. "Transitioned into 'post'"
  LOG_TRANSITIONS: true, 
  LOG_TRANSITIONS_INTERNAL: true
});
LIFX.ApplicationAdapter = DS.FixtureAdapter.extend();