import '../models.dart';

/// The one thing that would most help the sidekick pitch this person, or null when the profile
/// is complete. In order of how much each helps a match.
String? profileNudge(Profile p) {
  if (p.lookingFor.isEmpty) return 'Tell your sidekick what you’re looking for, so it knows who to find.';
  if (p.offering.isEmpty) return 'Add what you can offer. It’s how other sidekicks find you.';
  if (p.headline.trim().isEmpty) return 'Add what you do, so people know who they’re meeting.';
  if (p.photoURL.isEmpty) return 'Add a photo. People connect more with a face.';
  if (p.about.trim().isEmpty) return 'Add a line about what you’re working on. Your sidekick uses it in its pitch.';
  return null;
}

/// "Good morning", "Good afternoon" or "Good evening", for the hour.
String greeting(DateTime now) {
  if (now.hour < 5) return 'Good evening';
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}
