// Stage 10 Part 5d: opt-out words per language (docs/global-sms-behavior-contract.md § Part 5).
//
// Twilio handles the English words on its own (STOP, UNSUBSCRIBE, CANCEL, START…). Every other language works
// only once someone adds its words to the business's messaging service in Advanced Opt-Out, because Twilio
// matches the words it is told and translates nothing. A country's language is its main language from the
// Unicode CLDR likely-subtags data the browser already carries (`und-MX` → Spanish), plus the second official
// language of countries that text in two. Languages Twilio's Advanced Opt-Out cannot take stay English-only.
//
// The app also reads these words itself, so a customer who replies ALTO is stopped even before Twilio is set up.

export type OptOutLanguage = {
	/** English name, as Twilio's language list shows it. */
	name: string;
	stop: string[];
	start: string[];
	/** What Twilio replies after a stop word. */
	stopReply: string;
	/** What Twilio replies after a start word. */
	startReply: string;
};

/** Every language Twilio's Advanced Opt-Out takes that is the main language of a country, keyed by its code. */
export const OPT_OUT_LANGUAGES: Record<string, OptOutLanguage> = {
	af: {
		name: 'Afrikaans',
		stop: ['STAAK', 'KANSELLEER'],
		start: ['BEGIN'],
		stopReply: 'Jy is afgemeld en sal nie meer boodskappe ontvang nie.',
		startReply: 'Jy ontvang weer boodskappe.'
	},
	ar: {
		name: 'Arabic',
		stop: ['توقف', 'إلغاء', 'الغاء'],
		start: ['ابدأ', 'ابدا'],
		stopReply: 'تم إلغاء اشتراكك ولن تتلقى المزيد من الرسائل.',
		startReply: 'ستتلقى الرسائل مجددًا.'
	},
	bn: {
		name: 'Bengali',
		stop: ['বন্ধ', 'বাতিল', 'BONDHO'],
		start: ['শুরু'],
		stopReply: 'আপনি সদস্যতা বাতিল করেছেন। আর কোনো বার্তা পাবেন না।',
		startReply: 'আপনি আবার বার্তা পাবেন।'
	},
	cs: {
		name: 'Czech',
		stop: ['KONEC', 'ZRUŠIT', 'ZRUSIT', 'ODHLÁSIT', 'ODHLASIT'],
		start: ['PŘIHLÁSIT', 'PRIHLASIT'],
		stopReply: 'Byli jste odhlášeni a už nedostanete žádné zprávy.',
		startReply: 'Znovu dostáváte zprávy.'
	},
	da: {
		name: 'Danish',
		stop: ['AFMELD', 'STOPPE'],
		start: ['TILMELD'],
		stopReply: 'Du er afmeldt og modtager ikke flere beskeder.',
		startReply: 'Du modtager beskeder igen.'
	},
	de: {
		name: 'German',
		stop: ['STOPP', 'ABMELDEN', 'BEENDEN'],
		start: ['ANMELDEN'],
		stopReply: 'Sie wurden abgemeldet und erhalten keine weiteren Nachrichten.',
		startReply: 'Sie erhalten wieder Nachrichten.'
	},
	el: {
		name: 'Greek',
		stop: ['ΔΙΑΚΟΠΗ', 'ΣΤΟΠ'],
		start: ['ΕΝΑΡΞΗ'],
		stopReply: 'Έχετε απεγγραφεί και δεν θα λαμβάνετε άλλα μηνύματα.',
		startReply: 'Λαμβάνετε ξανά μηνύματα.'
	},
	es: {
		name: 'Spanish',
		stop: ['ALTO', 'PARAR', 'CANCELAR', 'BAJA'],
		start: ['INICIO', 'SÍ'],
		stopReply: 'Te has dado de baja. No recibirás más mensajes.',
		startReply: 'Vuelves a recibir mensajes.'
	},
	et: {
		name: 'Estonian',
		stop: ['LOOBU', 'LÕPETA'],
		start: ['ALUSTA'],
		stopReply: 'Olete loobunud ega saa enam sõnumeid.',
		startReply: 'Saate taas sõnumeid.'
	},
	fi: {
		name: 'Finnish',
		stop: ['LOPETA', 'PERU'],
		start: ['ALOITA'],
		stopReply: 'Tilauksesi on peruttu. Et saa enää viestejä.',
		startReply: 'Saat taas viestejä.'
	},
	fr: {
		name: 'French',
		stop: ['ARRET', 'ARRÊT', 'DESABONNER', 'DÉSABONNER'],
		start: ['COMMENCER'],
		stopReply: 'Vous êtes désabonné. Vous ne recevrez plus de messages.',
		startReply: 'Vous recevez à nouveau nos messages.'
	},
	he: {
		name: 'Hebrew',
		stop: ['הסר', 'עצור', 'הפסק'],
		start: ['התחל'],
		stopReply: 'הוסרת ולא תקבל עוד הודעות.',
		startReply: 'תקבל שוב הודעות.'
	},
	hi: {
		name: 'Hindi',
		stop: ['बंद', 'रोकें'],
		start: ['शुरू'],
		stopReply: 'आपने सदस्यता छोड़ दी है। अब आपको संदेश नहीं मिलेंगे।',
		startReply: 'आपको फिर से संदेश मिलेंगे।'
	},
	hr: {
		name: 'Croatian',
		stop: ['ODJAVA', 'ZAUSTAVI'],
		start: ['PRIJAVA'],
		stopReply: 'Odjavljeni ste i više nećete primati poruke.',
		startReply: 'Ponovno primate poruke.'
	},
	hu: {
		name: 'Hungarian',
		stop: ['LEIRATKOZÁS', 'LEIRATKOZAS'],
		start: ['FELIRATKOZÁS', 'FELIRATKOZAS'],
		stopReply: 'Leiratkozott, több üzenetet nem kap.',
		startReply: 'Újra kap üzeneteket.'
	},
	it: {
		name: 'Italian',
		stop: ['BASTA', 'ANNULLA', 'DISISCRIVI'],
		start: ['ISCRIVI'],
		stopReply: "Hai annullato l'iscrizione. Non riceverai più messaggi.",
		startReply: 'Riceverai di nuovo i messaggi.'
	},
	ja: {
		name: 'Japanese',
		stop: ['停止', '配信停止', 'ストップ'],
		start: ['開始'],
		stopReply: '配信を停止しました。今後メッセージは届きません。',
		startReply: 'メッセージの配信を再開しました。'
	},
	ko: {
		name: 'Korean',
		stop: ['중지', '거부', '수신거부'],
		start: ['시작'],
		stopReply: '수신 거부되었습니다. 더 이상 메시지를 받지 않습니다.',
		startReply: '메시지를 다시 받습니다.'
	},
	lt: {
		name: 'Lithuanian',
		stop: ['ATSISAKYTI', 'SUSTABDYTI'],
		start: ['UŽSISAKYTI', 'UZSISAKYTI'],
		stopReply: 'Jūs atsisakėte ir nebegausite žinučių.',
		startReply: 'Vėl gaunate žinutes.'
	},
	lv: {
		name: 'Latvian',
		stop: ['ATTEIKTIES', 'PĀRTRAUKT', 'PARTRAUKT'],
		start: ['PIETEIKTIES'],
		stopReply: 'Jūs esat atteicies un vairs nesaņemsiet ziņas.',
		startReply: 'Jūs atkal saņemat ziņas.'
	},
	ms: {
		name: 'Malay',
		stop: ['BERHENTI', 'HENTI'],
		start: ['MULA'],
		stopReply: 'Anda telah berhenti melanggan dan tidak akan menerima mesej lagi.',
		startReply: 'Anda akan menerima mesej semula.'
	},
	nb: {
		name: 'Norwegian',
		stop: ['STOPP', 'AVSLUTT', 'AVMELD'],
		start: ['PÅMELD'],
		stopReply: 'Du er avmeldt og får ikke flere meldinger.',
		startReply: 'Du får meldinger igjen.'
	},
	nl: {
		name: 'Dutch',
		stop: ['STOPPEN', 'AFMELDEN', 'UITSCHRIJVEN'],
		start: ['AANMELDEN'],
		stopReply: 'Je bent afgemeld. Je ontvangt geen berichten meer.',
		startReply: 'Je ontvangt weer berichten.'
	},
	pl: {
		name: 'Polish',
		stop: ['ZATRZYMAJ', 'REZYGNUJ', 'WYPISZ'],
		start: ['ZAPISZ'],
		stopReply: 'Wypisano Cię. Nie otrzymasz więcej wiadomości.',
		startReply: 'Ponownie otrzymujesz wiadomości.'
	},
	pt: {
		name: 'Portuguese',
		stop: ['PARAR', 'SAIR', 'CANCELAR', 'DESCADASTRAR'],
		start: ['INICIAR'],
		stopReply: 'Você cancelou a inscrição. Não receberá mais mensagens.',
		startReply: 'Você voltou a receber mensagens.'
	},
	ru: {
		name: 'Russian',
		stop: ['СТОП', 'ОТПИСАТЬСЯ', 'ОТМЕНА'],
		start: ['СТАРТ', 'ПОДПИСАТЬСЯ'],
		stopReply: 'Вы отписались и больше не будете получать сообщения.',
		startReply: 'Вы снова получаете сообщения.'
	},
	sk: {
		name: 'Slovak',
		stop: ['KONIEC', 'ZRUŠIŤ', 'ZRUSIT', 'ODHLÁSIŤ', 'ODHLASIT'],
		start: ['PRIHLÁSIŤ', 'PRIHLASIT'],
		stopReply: 'Boli ste odhlásení a už nedostanete žiadne správy.',
		startReply: 'Opäť dostávate správy.'
	},
	sl: {
		name: 'Slovene',
		stop: ['ODJAVA', 'USTAVI'],
		start: ['PRIJAVA'],
		stopReply: 'Odjavljeni ste in ne boste več prejemali sporočil.',
		startReply: 'Ponovno prejemate sporočila.'
	},
	sv: {
		name: 'Swedish',
		stop: ['STOPPA', 'AVSLUTA', 'AVREGISTRERA'],
		start: ['STARTA'],
		stopReply: 'Du är avregistrerad och får inga fler meddelanden.',
		startReply: 'Du får meddelanden igen.'
	},
	zh: {
		name: 'Chinese',
		stop: ['退订', '退訂', '取消', 'TD'],
		start: ['订阅', '訂閱'],
		stopReply: '您已退订，将不再收到消息。',
		startReply: '您将重新收到消息。'
	}
};

/** Countries that text in a second official language besides their main one. */
const SECOND_LANGUAGES: Record<string, string[]> = {
	BE: ['fr'],
	CA: ['fr'],
	CH: ['fr', 'it'],
	LU: ['de']
};

/** The main language of a country, from CLDR likely subtags ("MX" → "es"). */
function mainLanguage(country: string): string | null {
	try {
		const language = new Intl.Locale(`und-${country}`).maximize().language;
		// Norwegian Bokmål is what Twilio lists as Norwegian.
		return language === 'no' ? 'nb' : language;
	} catch {
		return null;
	}
}

/**
 * The languages beyond English a business needs opt-out words for before it texts a country, in the order
 * Twilio's console should get them. Empty for English-speaking countries and for languages Twilio's Advanced
 * Opt-Out cannot take, where the English words are what works.
 */
export function countryOptOutLanguages(country: string): string[] {
	const code = country.toUpperCase();
	const languages = [mainLanguage(code), ...(SECOND_LANGUAGES[code] ?? [])];
	return [...new Set(languages)].filter(
		(language): language is string => !!language && language in OPT_OUT_LANGUAGES
	);
}

/** "Turkish", "Spanish": a language's English name from the browser's own list. */
export function languageName(code: string): string {
	return (
		OPT_OUT_LANGUAGES[code]?.name ??
		new Intl.DisplayNames(['en'], { type: 'language' }).of(code) ??
		code
	);
}

/** A country's main language when Twilio has no opt-out words for it ("TR" → "tr"), else null. */
export function englishOnlyLanguage(country: string): string | null {
	const language = mainLanguage(country.toUpperCase());
	if (!language || language === 'en' || language in OPT_OUT_LANGUAGES) return null;
	return language;
}

const normalize = (word: string) => word.normalize('NFC').trim().toLocaleLowerCase();

const KEYWORDS = new Map<string, 'opt_out' | 'opt_in'>();
for (const language of Object.values(OPT_OUT_LANGUAGES)) {
	for (const word of language.stop) KEYWORDS.set(normalize(word), 'opt_out');
	for (const word of language.start) KEYWORDS.set(normalize(word), 'opt_in');
}

/** Whether a whole reply is one of the non-English stop or start words. Null for an ordinary reply. */
export function optOutKeywordKind(body: string): 'opt_out' | 'opt_in' | null {
	return KEYWORDS.get(normalize(body)) ?? null;
}
