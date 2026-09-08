import type { Metadata } from 'next'

import { LegalPage } from '../../components/LegalPage'

export const metadata: Metadata = {
  title: 'Terms of Service',
  description:
    'Read the XapZap Terms of Service for the website and app, including user obligations, prohibited conduct, moderation rules, account enforcement, and deletion behavior.',
}

const sections = [
  {
    title: 'Agreement to these terms',
    body:
      'These Terms of Service govern access to and use of XapZap through the website, mobile app, Flutter web build, and related services. By accessing public content, creating an account, posting, commenting, following, liking, reporting, blocking, or otherwise using XapZap, the user agrees to these terms.',
  },
  {
    title: 'Eligibility and account integrity',
    body:
      'Users must provide accurate information, maintain the security of their credentials, and use only accounts they are authorized to control. Users are responsible for activity that occurs through their account unless they promptly report unauthorized access. XapZap may restrict, suspend, or remove accounts that violate eligibility rules, misrepresent identity, or expose the platform to legal or security risk.',
  },
  {
    title: 'Prohibited conduct',
    body:
      'Users must not use XapZap for unlawful conduct, harassment, bullying, hate speech, violent threats, terrorism support, sexual exploitation, child sexual abuse material, spam, scams, fraud, phishing, malware distribution, impersonation, account trading, deceptive identity use, coordinated manipulation, vote or engagement manipulation, or other abusive behavior. Attempts to bypass platform restrictions, evade enforcement, scrape protected data, abuse reporting systems, automate misuse, or interfere with normal service operation are also prohibited.',
  },
  {
    title: 'Privacy and contact restrictions',
    body:
      'Users must not post, request, trade, solicit, or encourage the sharing of personal contact details or sensitive personal information on XapZap when doing so could create privacy, fraud, stalking, or safety risk. This includes phone numbers, private email addresses, home addresses, banking details, passwords, one-time codes, government identifiers, or similar information. Users must not pressure other users to move to private messaging apps or off-platform channels for suspicious, exploitative, or unsafe activity.',
  },
  {
    title: 'User-generated content',
    body:
      'Users are responsible for the text, profile information, and other materials they submit to XapZap. By posting content, users represent that they have the right to share it and that it does not violate law, infringe third-party rights, or breach these terms. Public content may be viewed, shared, or referenced by others according to product design and platform availability.',
  },
  {
    title: 'Content restrictions',
    body:
      'Users must not publish content that is illegal, defamatory, infringing, misleading, sexually exploitative, graphically violent, privacy-invasive, or intended to facilitate fraud, trafficking, extortion, blackmail, doxxing, or real-world harm. Users must not impersonate individuals, brands, or public entities in a misleading way and must not misrepresent affiliation, endorsement, or authority.',
  },
  {
    title: 'Moderation and enforcement',
    body:
      'XapZap may review, restrict, remove, downrank, block, suspend, disable features on, or permanently ban content and accounts that violate these terms, the Privacy Policy, platform rules, or applicable law. Enforcement may be based on user reports, automated detection, internal review, trusted flaggers, or a combination of those methods. We may act without prior notice when safety, child protection, legal exposure, abuse prevention, or service integrity requires it.',
  },
  {
    title: 'Violations and consequences',
    body:
      'Violations of these terms can result in content removal, loss of visibility, feature restrictions, temporary suspension, permanent account bans, device or account blocking, and denial of future access to XapZap. Serious or repeated violations can lead to immediate enforcement without warning. XapZap may also preserve relevant records and cooperate with lawful requests, safety investigations, fraud investigations, or law enforcement where required.',
  },
  {
    title: 'Deletion and residual records',
    body:
      'Users can permanently delete their account through the supported deletion flow. XapZap attempts to remove core account data immediately after a confirmed deletion succeeds. Limited residual records may remain where required for security, moderation, fraud prevention, legal compliance, or system propagation.',
  },
  {
    title: 'Availability of the service',
    body:
      'XapZap may change, suspend, or discontinue features, ranking systems, posting capabilities, moderation systems, or access flows at any time. We do not guarantee uninterrupted availability, but aim to operate the platform responsibly and improve reliability over time.',
  },
  {
    title: 'Disclaimers and limitation of liability',
    body:
      'To the maximum extent permitted by law, XapZap is provided on an as available basis without guarantees of uninterrupted service, absolute security, or error-free operation. XapZap is not liable for indirect, incidental, special, consequential, or punitive damages arising from user-generated content, platform use, unavailable service, or third-party conduct, except where liability cannot be excluded under applicable law.',
  },
  {
    title: 'Changes to these terms',
    body:
      'We may revise these Terms of Service as the product, moderation systems, infrastructure, or legal requirements change. Updated terms may be published on the website, in the app, or both. Continued use of XapZap after the effective date of revised terms means the user accepts the updated terms to the extent allowed by law.',
  },
  {
    title: 'Contact',
    body:
      'For policy, moderation, or account questions, contact xapzaptech@gmail.com.',
  },
]

export default function TermsPage() {
  return (
    <LegalPage
      title="XapZap Terms of Service"
      eyebrow="Legal"
      intro="These Terms of Service govern use of XapZap on both the website and app and set the platform rules for account use, public content, safety, and enforcement."
      sections={sections}
      currentPath="/terms"
    />
  )
}
