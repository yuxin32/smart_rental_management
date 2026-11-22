/// Review material for the functional prototype, not published legal documents.
/// These client-side visibility rules are labeling safeguards, not authorization.
bool canPreviewLegalDrafts(String? environment, {bool localPreview = false}) =>
    environment == 'staging' ||
    (localPreview && (environment == null || environment == 'local'));

enum LegalDraftKind { terms, privacy }

class LegalDraftSection {
  const LegalDraftSection(this.title, this.body);
  final String title;
  final String body;
}

class PrototypeLegalDraft {
  const PrototypeLegalDraft(this.title, this.notice, this.sections);
  final String title;
  final String notice;
  final List<LegalDraftSection> sections;

  static const version = 'Information version 0.3 · Review pending';
  static const status = 'DRAFT — NOT PUBLISHED';
  static const releaseChecklist = [
    'Identify the legal operator and a real support / privacy contact.',
    'Approve the purposes, recipients, hosting locations and any cross-border data handling.',
    'Decide retention periods and implement account deletion, access / correction / export requests and backup handling.',
    'Define service disputes, early / late work, cancellation and any future payment / refund rules.',
    'Review security incident handling, applicable law and appropriate publication languages with qualified advice.',
    'Approve and publish versioned documents before public use; implement any required notice / consent process separately.',
  ];

  String get copyText => [
        title,
        status,
        version,
        notice,
        'No effective date or legal acceptance is recorded by this page.',
        for (final section in sections) '${section.title}\n${section.body}',
      ].join('\n\n');

  static PrototypeLegalDraft forKind(LegalDraftKind kind) =>
      kind == LegalDraftKind.terms ? terms : privacy;

  static const terms = PrototypeLegalDraft(
    'Terms of service',
    'These draft terms explain how to use Smart Rental. '
        'They have not been published as final terms. Read the service scope, quote and cancellation rules before requesting cleaning. Online payment is not offered in the App.',
    [
      LegalDraftSection('1. Using Smart Rental',
          'Owners can manage rental units and request cleaning. Providers can manage their services, availability and assigned bookings. Bookings, messages and uploaded photos are saved online. Closing the App does not remove them.'),
      LegalDraftSection('2. Accounts and responsibilities',
          'Use your own account. Keep your name, contact number and service information accurate. Keep passwords and verification codes private. Providers need approval before accepting work; selecting the Provider role alone does not grant approval.'),
      LegalDraftSection('3. Booking and prices',
          'Check the rental unit, service, date, Malaysia time and quoted price before sending a request. A Pending request does not reserve a slot. The booking is confirmed when the Provider accepts it, subject to availability. The quoted price covers the selected service and booked duration. A different duration requires a new priced request.'),
      LegalDraftSection('4. Included work and extra tasks',
          'Read the selected service description and confirm any unclear tasks with the Provider. Additional tasks to discuss are requests, not work automatically included in the quote. Both participants should agree on any changes before work starts. A new quote may be needed; adding a note does not change the saved price.'),
      LegalDraftSection('5. Changes and cancellations',
          'An Owner can change a Pending request while keeping the same duration, subject to availability and the rental unit cleaning window. Owners can cancel Pending requests. Either participant can cancel an Accepted booking before work starts and must give a reason. Cancellation is not available once the booking is In Progress. This version does not calculate cancellation fees or refunds.'),
      LegalDraftSection('6. Work and photos',
          'The assigned Provider updates the booking as work starts and finishes. Before and after photos are required to complete a job. Photos and a Completed status are records of the booking, not a guarantee of cleaning quality. Arrival guarantees and a policy for starting early or late have not been established. A status record alone is not proof of the quality or timing of a service.'),
      LegalDraftSection('7. Messages and reviews',
          'Use booking chat for relevant service details. New messages can be sent while a booking is Accepted or In Progress. When the booking closes, its conversation becomes read-only and previous messages remain available. Owners can leave a review for eligible Completed bookings. Keep messages and reviews respectful and avoid sharing unrelated private information.'),
      LegalDraftSection('8. Earnings and payments',
          'Earnings shows the saved value of completed jobs, not money received. Online payments, platform fee collection, refunds and Provider payouts are not available in this version. No payment is taken when you submit a request. Do not enter card or bank details in messages or cleaning instructions.'),
      LegalDraftSection('9. Connection problems and help',
          'If a request appears to stop, check your bookings or refresh the conversation before trying again. A timeout alone does not prove failure or success. Use the Help center for booking, availability and account guidance. If a support contact is listed, include the booking reference and a description of the issue. Never send your password or verification codes.'),
    ],
  );

  static const privacy = PrototypeLegalDraft(
    'Privacy policy',
    'This draft explains what information Smart Rental currently uses and shares. '
        'It has not been published as a final privacy notice. A formal privacy contact and full retention policy have not yet been published.',
    [
      LegalDraftSection('1. Information you provide',
          'Account information includes your name, email, contact number and Owner or Provider role. Owners provide rental unit details, including its address, bedrooms, size and permitted cleaning times. Providers provide service areas, a private service origin, rates, availability and profile details. Required fields are marked in the forms; without them, the relevant account, property or booking cannot be created. Optional notes and extra task requests can be left blank.'),
      LegalDraftSection('2. Why the App uses this information',
          'Smart Rental uses account information to sign you in and identify your role. Property details, service choices, times, rates and Provider availability help find suitable Providers and manage bookings. The App also saves booking changes, cancellation reasons, messages, photos, reviews and notifications so participants can follow their jobs and view their records.'),
      LegalDraftSection('3. Information shared for a booking',
          'The Owner and the assigned Provider can view the booking details, messages and permitted job photos. This includes the rental unit address, even while the request is Pending; do not assume it is hidden until acceptance. Provider listings show service and profile information, while the private service origin is not shown in the directory. Review ratings can contribute to Provider statistics.'),
      LegalDraftSection('4. Photos and camera or gallery access',
          'The App uses photos you choose or take for a booking. Selecting a photo starts its upload; check it before selecting it. The App does not upload your whole gallery. Photos are resized and processed to remove original embedded metadata, but visible faces, documents or other private details can remain in the image. Avoid including them. You can manage camera and photo permissions in your phone settings. Removing a permission does not delete photos already uploaded.'),
      LegalDraftSection('5. Online storage and access',
          'Account sign-in and App data are hosted using Supabase. Booking and photo access is restricted according to the account and booking participants. Authorized App operators and hosting providers may also access information within their permissions. Chat is not end-to-end encrypted, so it is not a promise that only two people can ever access a message. Do not share passwords, bank details or unrelated sensitive information in chat or notes.'),
      LegalDraftSection('6. Information on your device',
          'The App keeps sign-in information on your device so you can stay signed in, and temporarily keeps recently opened information and photos to reduce repeated downloads. Android sign-in information uses platform secure storage. The browser version uses browser session storage. Protect your device and sign out on shared devices. Signing out does not delete cloud bookings, photos or messages.'),
      LegalDraftSection('7. Correcting or removing information',
          'You can update supported profile and rental unit details in the App. Account deletion and data export are not yet available as self-service features. A fixed retention period and a process for removing records and backups have not yet been published. Closing the App, signing out or uninstalling it does not delete your online records. Use a published privacy contact when available to ask about information rights or record removal.'),
      LegalDraftSection('8. Privacy questions',
          'A formal privacy contact has not yet been published. The Help center provides general information; opening it does not submit a request for access to or deletion of your information. Do not include passwords, verification codes or unrelated sensitive details when contacting the App operator through a published channel.'),
    ],
  );
}
