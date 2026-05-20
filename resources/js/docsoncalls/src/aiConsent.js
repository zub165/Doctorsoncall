const CONSENT_KEY = 'docsoncalls_ai_consent_v1';
const CONSENT_VERSION = '1';

export const AI_CONSENT = {
  operator: 'Innovator Generation',
  endpoint: 'https://api.docsoncalls.com/api/medical-records/ai-assist/',
  processor: 'Ollama (open-source LLM on Docs On Call servers)',
  privacyUrl: 'https://docsoncalls.com/privacy.html',
};

export function hasAiConsent() {
  try {
    return (
      localStorage.getItem(CONSENT_KEY) === 'true' &&
      localStorage.getItem(`${CONSENT_KEY}_version`) === CONSENT_VERSION
    );
  } catch {
    return false;
  }
}

export function saveAiConsent() {
  localStorage.setItem(CONSENT_KEY, 'true');
  localStorage.setItem(`${CONSENT_KEY}_version`, CONSENT_VERSION);
}

export function revokeAiConsent() {
  localStorage.removeItem(CONSENT_KEY);
  localStorage.removeItem(`${CONSENT_KEY}_version`);
}

/** Returns true if user allowed sending data. */
export async function ensureAiConsent({ includesHealthRecords = false } = {}) {
  if (hasAiConsent()) return true;

  const ok = window.confirm(
    [
      'Allow AI to process your information?',
      '',
      'What may be sent: text you type' +
        (includesHealthRecords ? ' and selected record excerpts' : '') +
        '.',
      'Who receives it: ' + AI_CONSENT.operator + ' via ' + AI_CONSENT.endpoint,
      'Processed by: ' + AI_CONSENT.processor + '.',
      'We do not sell your data or send it to ChatGPT for training.',
      'Not for emergencies. Privacy: ' + AI_CONSENT.privacyUrl,
      '',
      'Press OK to allow, Cancel to decline.',
    ].join('\n'),
  );

  if (ok) {
    saveAiConsent();
    return true;
  }
  return false;
}
