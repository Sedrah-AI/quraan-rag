import 'api_config.dart';

/// URL for one word's existing reference-pronunciation clip - already
/// servable with zero backend changes (see the main repo's
/// content-service `words.audio_asset_id`, one fixed clip per word, not
/// tied to any particular reciter). wordIndex is 1-based.
String wordAudioUrl(int surahId, int ayahId, int wordIndex) =>
    '$kApiBaseUrl/api/words/$surahId/$ayahId/$wordIndex/audio';
