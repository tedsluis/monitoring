// renovate-config.js
// This is the configuration for the Renovate bot itself (the "runner").
module.exports = {
  platform: 'github',
  // Put your GitHub repository here (adjust if needed)
  repositories: ['tedsluis/monitoring'],
  
  // Because we manage things ourselves, skip the automatic onboarding
  onboarding: false,
  
  // Ensures Renovate looks for renovate.json in the root of your repo
  requireConfig: 'optional'
};