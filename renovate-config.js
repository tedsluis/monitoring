// renovate-config.js
// Dit is de configuratie voor de Renovate bot zelf (de "runner").
module.exports = {
  platform: 'github',
  // Zet hier jouw GitHub repository neer (aanpassen indien nodig)
  repositories: ['tedsluis/monitoring'],
  
  // Omdat we de boel zelf beheren, slaan we de automatische onboarding over
  onboarding: false,
  
  // Zorgt ervoor dat Renovate zoekt naar renovate.json in de root van je repo
  requireConfig: 'optional'
};