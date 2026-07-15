/// Backend base URL. Only the "your turn" recording step needs this at
/// all - everything else (text, audio, word timings) is bundled offline
/// (see assets/data/al_fatiha.json).
///
/// Currently pointed at a temporary Cloudflare quick tunnel to the dev
/// backend (started 2026-07-15, ad-hoc *.trycloudflare.com URL - not a
/// stable domain, dies whenever that tunnel process stops and gets a
/// different URL if restarted). Replace with a real deployed domain
/// before this app goes further than local device testing - see
/// wiki/Deployment.md in the main repo for the general "how to deploy
/// this system" story.
const String kApiBaseUrl = 'https://crew-indoor-pentium-professor.trycloudflare.com';
const String kWsBaseUrl = 'wss://crew-indoor-pentium-professor.trycloudflare.com';
