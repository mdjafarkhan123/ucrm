// Prints the SQL rows for private.sms_phone_time_zone_prefixes: the time zones a phone number can be in, by its
// longest matching leading digits. Built from Google libphonenumber's own time zone map (the data behind its
// PhoneNumberToTimeZonesMapper), so quiet hours follow the customer's clock. Re-run with a newer release tag:
//   curl -sfL -o map_data.txt https://raw.githubusercontent.com/google/libphonenumber/v9.0.41/resources/timezones/map_data.txt
//   node scripts/generate-phone-time-zones.mjs map_data.txt > rows.sql
import { readFileSync } from 'node:fs';

const [file] = process.argv.slice(2);
if (!file) {
	console.error('Usage: node scripts/generate-phone-time-zones.mjs <map_data.txt>');
	process.exit(1);
}

const rows = readFileSync(file, 'utf8')
	.split('\n')
	.map((line) => line.trim())
	.filter((line) => line && !line.startsWith('#'))
	.map((line) => {
		const [prefix, zones] = line.split('|');
		return [prefix, zones.split('&').sort()];
	})
	.sort(([a], [b]) => a.localeCompare(b));

const quote = (value) => `'${value.replaceAll("'", "''")}'`;
console.log(
	rows
		.map(([prefix, zones]) => `(${quote(prefix)}, array[${zones.map(quote).join(', ')}])`)
		.join(',\n') + '\n;'
);
