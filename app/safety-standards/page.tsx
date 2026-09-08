import type { Metadata } from 'next'

import { LegalPage } from '../../components/LegalPage'

export const metadata: Metadata = {
  title: 'Safety Standards',
  description:
    'Read XapZap safety standards against child sexual abuse and exploitation, including prohibited conduct, user obligations, reporting, moderation, investigations, and enforcement consequences.',
}

const sections = [
  {
    title: 'Purpose of these safety standards',
    body:
      'These Safety Standards explain XapZap rules against child sexual abuse and exploitation. They apply across the XapZap website, app, public profile surfaces, posting tools, comments, account interactions, and related services. These standards are intended to protect children, support rapid enforcement, and make clear that XapZap does not permit any use of the service that sexualizes, endangers, exploits, traffics, grooms, or otherwise harms minors.',
  },
  {
    title: 'Zero-tolerance standard',
    body:
      'XapZap has zero tolerance for child sexual abuse and exploitation. Users must not use XapZap to create, upload, post, store, request, advertise, promote, search for, share, sell, distribute, exchange, or facilitate child sexual abuse material, sexualized content involving minors, grooming, sextortion, child trafficking, or any other form of child sexual exploitation. This rule applies whether the conduct is explicit, coded, disguised, attempted, threatened, encouraged, linked, or coordinated through off-platform contact.',
  },
  {
    title: 'Content that is strictly prohibited',
    body:
      'Users must not post or attempt to exchange child sexual abuse material, nudity involving minors, sexually explicit depictions of minors, exploitative role-play involving minors, manipulated or synthetic sexualized depictions of minors, or content that praises, normalizes, glorifies, jokes about, or encourages sexual abuse of children. Users must not post instructions, directories, coded tags, or distribution methods for finding, hiding, trading, or preserving exploitative content involving children.',
  },
  {
    title: 'Grooming, solicitation, and predatory conduct',
    body:
      'Users must not use XapZap to contact minors for sexual purposes, build deceptive trust with a minor for future sexual exploitation, solicit sexual images or videos from minors, request private contact details from minors, coerce minors into secrecy, pressure minors to move to private channels, or threaten, blackmail, manipulate, or extort minors. Users must not use compliments, gifts, promises, intimidation, emotional pressure, or authority claims to exploit children or to prepare children for exploitation.',
  },
  {
    title: 'Off-platform coordination is also prohibited',
    body:
      'Users must not use XapZap to direct any person, and especially any minor, to encrypted chats, private messaging apps, temporary links, hidden websites, or other off-platform channels for sexual exploitation, sexual contact, trafficking, or evasion of moderation. Attempts to move abusive conduct off XapZap still violate these standards even if the final exploitative act occurs somewhere else.',
  },
  {
    title: 'No evasion, disguise, or coded behavior',
    body:
      'Users must not use coded language, symbols, hashtags, shortened links, indirect requests, role descriptions, fake age claims, selective cropping, blurred previews, staged profiles, or other evasion techniques to hide child sexual abuse or exploitation activity. Users must not impersonate minors, misstate a child’s age, falsify guardianship, or misrepresent identity in order to gain access to children or to conceal abusive conduct.',
  },
  {
    title: 'Protection of minors in profiles, posts, and comments',
    body:
      'Users must not use profile names, bios, avatars, comments, text posts, or account interactions to sexualize minors or to encourage unsafe communication with minors. Users must not ask minors to share personal contact details, location details, school details, family information, sexual content, or private images. Users must not pressure minors to keep conversations secret from parents, guardians, teachers, or authorities.',
  },
  {
    title: 'Reporting obligations for users',
    body:
      'Users who encounter suspected child sexual abuse or exploitation content on XapZap should report it immediately through the in-app reporting tools or by contacting xapzaptech@gmail.com. Users must not reshare, download, store, trade, quote, repost, circulate, or otherwise amplify suspected abusive material. Reporting should be immediate, and users should avoid engaging with the abusive account except where necessary to preserve basic identifying details for a report.',
  },
  {
    title: 'Moderation review and investigations',
    body:
      'XapZap can investigate reports, preserve relevant evidence where required, review account activity, examine associated interaction records, restrict visibility, disable features, remove content, and permanently ban accounts involved in child sexual abuse or exploitation. Investigations can include review of reports, account history, linked activity, repeat-offender patterns, technical abuse indicators, and other trust and safety signals. Serious violations can result in immediate enforcement without warning.',
  },
  {
    title: 'Evidence preservation and legal cooperation',
    body:
      'Where required by law, safety obligations, or legitimate child protection needs, XapZap can preserve relevant records relating to suspected child sexual abuse or exploitation. This can include account identifiers, moderation records, reports, interaction records, and technical evidence needed for review or lawful disclosure. XapZap can cooperate with lawful requests, child safety organizations, regulators, or law enforcement where required by law or where necessary to protect children.',
  },
  {
    title: 'Account and access consequences',
    body:
      'Accounts involved in child sexual abuse or exploitation can be permanently banned, removed from the service, blocked from future access, referred for additional review, and denied re-registration. Related content can be removed immediately. Associated devices, linked accounts, related accounts, and repeat-offender patterns can also be reviewed for enforcement. XapZap can restrict or terminate access without prior notice when child safety requires immediate action.',
  },
  {
    title: 'Child safety takes priority over reach or engagement',
    body:
      'XapZap does not treat child safety violations as ordinary content disputes. Child sexual abuse and exploitation concerns override engagement goals, audience growth, creator status, monetization interests, or account history. A user does not gain protection from enforcement because of popularity, follower count, account age, or prior platform activity.',
  },
  {
    title: 'False reporting and misuse',
    body:
      'Users must not weaponize child safety reporting tools to harass, intimidate, or falsely accuse others. False or abusive reporting can lead to enforcement action. However, good-faith reporting of suspected child exploitation is encouraged, and users should report genuine concerns promptly even if they are uncertain about the full context.',
  },
  {
    title: 'Updates to these standards',
    body:
      'XapZap can update these Safety Standards as child safety expectations, legal obligations, platform risks, or moderation systems change. Updated standards can be published on the website, in the app, or both. Continued use of XapZap after updated standards become effective means the user remains bound by the latest published child safety rules to the extent permitted by law.',
  },
  {
    title: 'Contact',
    body:
      'For urgent safety concerns or questions about these standards, contact xapzaptech@gmail.com.',
  },
]

export default function SafetyStandardsPage() {
  return (
    <LegalPage
      title="XapZap Safety Standards Against CSAE"
      eyebrow="Safety"
      intro="This page sets out XapZap public standards against child sexual abuse and exploitation. It explains the conduct prohibited on XapZap, the obligations users must follow, how reporting works, and the enforcement consequences for any account involved in child sexual abuse or exploitation."
      sections={sections}
      currentPath="/safety-standards"
    />
  )
}
