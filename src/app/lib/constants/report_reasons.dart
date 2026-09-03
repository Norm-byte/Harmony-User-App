/// Shared report reason options used by every "Report" sheet in the app
/// (chat, community room, home screen reels/featured content, topics videos).
/// Each reason has a short caption clarifying what it covers, similar to
/// Facebook's report flow, so users don't default to an overly strong option.
class ReportReason {
  final String label;
  final String caption;

  const ReportReason(this.label, this.caption);
}

const List<ReportReason> kReportReasons = [
  ReportReason(
    'Spam or scam',
    'Repetitive, irrelevant, or deceptive content meant to mislead or promote something unrelated.',
  ),
  ReportReason(
    'Nudity or sexual content',
    'Sexually explicit content or nudity not appropriate for this community.',
  ),
  ReportReason(
    'Violence or graphic content',
    'Depicts real or graphic violence, gore, or disturbing imagery.',
  ),
  ReportReason(
    'Hate speech or harassment',
    'Attacks, insults, or targets a person or group based on identity, or is bullying/harassing.',
  ),
  ReportReason(
    'Misinformation',
    'Presents false or misleading claims as fact.',
  ),
  ReportReason(
    'Dangerous acts or self-harm risk',
    'Encourages risky behaviour, self-harm, or physical danger to yourself or others.',
  ),
  ReportReason(
    'Intellectual property concern',
    'Uses copyrighted or trademarked material without permission.',
  ),
  ReportReason(
    'Something else',
    'Doesn\'t fit the options above — please explain below.',
  ),
];
