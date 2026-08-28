/**
 * The widget's phone-number surface, isolated in its own module so the metadata behind it can be
 * code-split away from the widget's first byte.
 *
 * Re-exporting exactly the four things the widget uses is what keeps tree-shaking alive: importing
 * `libphonenumber-js/min` dynamically and holding its namespace object would stop Rollup from
 * proving the rest of the library unused, and drag it into the chunk as well.
 */

export {
	AsYouType,
	getCountries,
	getCountryCallingCode,
	parsePhoneNumberFromString
} from 'libphonenumber-js/min';
