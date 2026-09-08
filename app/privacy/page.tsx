import type { Metadata } from 'next'

import { LegalPage } from '../../components/LegalPage'

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description:
    'Read the XapZap Privacy Policy for the website and app, including account data, public content, moderation, retention, deletion, and user rights.',
}

const sections = [
  {
    title: 'Scope of this Privacy Policy',
    body:
      'This Privacy Policy applies to XapZap services made available through the website, mobile app, Flutter web experience, and supporting platform infrastructure. It explains how XapZap collects, uses, stores, discloses, protects, moderates, and deletes information when users browse public pages, create accounts, publish content, interact with other users, or contact support.',
  },
  {
    title: 'Information we collect',
    body:
      'XapZap collect account data such as email address, username, display name, date of birth, country, gender, profile biography, avatar, and cover image. We also collect user-generated content and platform interaction data such as posts, comments, likes, follows, saves, reports, blocks, moderation events, and account actions. Technical and operational information may include IP address, session timestamps, device details, browser details, app version details, crash data, and performance signals needed to run the service responsibly.',
  },
  {
    title: 'How we use information',
    body:
      'We use information to create and authenticate accounts, deliver public and personalized content, display profiles, enable posting and commenting, investigate reports, enforce moderation rules, secure the platform, detect fraud or abuse, maintain service performance, and comply with legal obligations. We may also use operational signals to improve reliability, ranking quality, abuse detection, child safety controls, and user safety systems.',
  },
  {
    title: 'How data may be shared',
    body:
      'Public profile information, public posts, comments, and public engagement signals may be visible to other users according to product design. XapZap may also use infrastructure and service providers for authentication, storage, networking, hosting, delivery, logging, and security support. Supported traffic is expected to be encrypted in transit through HTTPS or TLS.',
  },
  {
    title: 'Sensitive information and contact safety',
    body:
      'Users should not share sensitive personal data on XapZap. This includes phone numbers, home or work addresses, personal email addresses, bank or card details, passwords, one-time codes, national identity numbers, passport details, or other information that could expose the user or another person to fraud, stalking, impersonation, account takeover, or offline harm. XapZap may remove content that exposes private personal information or encourages off-platform contact in suspicious or unsafe ways.',
  },
  {
    title: 'Moderation, safety, and abuse prevention',
    body:
      'Reports, blocks, moderation decisions, and abuse indicators may be processed to detect harassment, hate speech, threats, impersonation, scams, spam, fraudulent solicitation, sexual exploitation, child safety violations, doxxing, coordinated abuse, and other prohibited behavior. We may retain relevant moderation information where reasonably necessary for trust and safety review, repeat-offender detection, security investigations, legal compliance, and dispute handling.',
  },
  {
    title: 'Deletion and retention',
    body:
      'Signed-in users can permanently delete their account through the supported deletion flow. XapZap attempts to remove the profile, posts, comments, likes, follows, saves, blocks, reports, and related account records immediately when deletion succeeds. Limited residual technical, safety, or legal records may remain only where necessary for propagation, fraud prevention, security review, moderation history, dispute handling, or legal compliance.',
  },
  {
    title: 'User rights and choices',
    body:
      'Users may update profile information, block accounts, report content, and use the supported account deletion flow. Depending on applicable law, users may also have rights to request access, correction, erasure, objection, or restriction relating to certain personal data. Requests may be limited where exceptions apply under law or where identity verification is required.',
  },
  {
    title: 'Children and age restrictions',
    body:
      'XapZap is not intended for users below the minimum legal age in their jurisdiction. If XapZap learns that an account was created in violation of age requirements, the account and related content may be restricted or removed.',
  },
  {
    title: 'International use',
    body:
      'Users may access XapZap from multiple countries and regions. Information may be processed in locations where XapZap or its infrastructure providers operate. XapZap seeks to apply reasonable safeguards consistent with the providers and systems it uses.',
  },
  {
    title: 'Policy updates',
    body:
      'XapZap may update this Privacy Policy as the product, moderation systems, infrastructure, and legal obligations evolve. Updated versions may be published on the website, in the app, or both. Continued use of the service after an effective date means the user accepts the revised policy to the extent permitted by law.',
  },
  {
    title: 'Contact',
    body:
      'For privacy, moderation, or account questions, contact xapzaptech@gmail.com.',
  },
]

export default function PrivacyPage() {
  return (
    <LegalPage
      title="XapZap Privacy Policy"
      eyebrow="Legal"
      intro="This Privacy Policy explains how XapZap handles account data, public content, moderation records, and account deletion across both the website and app."
      sections={sections}
      currentPath="/privacy"
    />
  )
}
