import re
import pandas as pd

# Upstream only accepted "d/m/yy, HH:MM - ". German (and most non-US) exports
# use dots -> "20.12.25, 21:33 - ", so nothing matched and the analysis silently
# came out empty. Accept . / and - as separators, 2- or 4-digit years, optional
# seconds and optional AM/PM (WhatsApp puts a narrow no-break space, U+202F,
# in front of it).
DATE_PATTERN = (
    r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4},[\s ]'
    r'\d{1,2}:\d{2}(?::\d{2})?(?:[\s ]?[APap]\.?[Mm]\.?)?[\s ]-\s'
)

# Tried in order; the first format that parses every timestamp wins.
# Day-first comes first because that is what upstream assumed (%d/%m/%Y).
DATE_FORMATS = [
    '%d.%m.%y, %H:%M', '%d.%m.%Y, %H:%M',
    '%d/%m/%y, %H:%M', '%d/%m/%Y, %H:%M',
    '%d-%m-%y, %H:%M', '%d-%m-%Y, %H:%M',
    '%m/%d/%y, %H:%M', '%m/%d/%Y, %H:%M',
    '%d.%m.%y, %H:%M:%S', '%d/%m/%Y, %H:%M:%S',
    '%d/%m/%y, %I:%M %p', '%m/%d/%y, %I:%M %p',
    '%d/%m/%Y, %I:%M %p', '%m/%d/%Y, %I:%M %p',
]


def _parse_dates(raw):
    """Turn the matched timestamp strings into datetimes.

    Tries the known WhatsApp layouts before falling back to pandas' own
    day-first guessing, so a locale we did not list still parses.
    """
    cleaned = (raw.str.replace(' ', ' ', regex=False)
                  .str.replace(r'\s*-\s*$', '', regex=True)
                  .str.strip())
    for fmt in DATE_FORMATS:
        parsed = pd.to_datetime(cleaned, format=fmt, errors='coerce')
        if parsed.notna().all():
            return parsed
    return pd.to_datetime(cleaned, dayfirst=True, errors='coerce')


def preprocess(data):
    # Strip the bidi marks WhatsApp injects in front of system messages,
    # they would otherwise end up inside user names.
    data = data.replace('‎', '').replace('‏', '')

    messages = re.split(DATE_PATTERN, data)[1:]
    dates = re.findall(DATE_PATTERN, data)

    df = pd.DataFrame({'user_message': messages, 'message_date': dates})
    # convert message_date type
    df['message_date'] = _parse_dates(df['message_date'])

    df.rename(columns={'message_date': 'date'}, inplace=True)

    users = []
    messages = []
    for message in df['user_message']:
        # Raw string: '\w' and '\s' are invalid escapes in a normal literal and
        # raise SyntaxWarning on Python 3.12+ (an error in a future release).
        # (upstream PR #39)
        entry = re.split(r'([\w\W]+?):\s', message)
        if entry[1:]:  # user name
            users.append(entry[1])
            messages.append(" ".join(entry[2:]))
        else:
            users.append('group_notification')
            messages.append(entry[0])

    df['user'] = users
    df['message'] = messages
    df.drop(columns=['user_message'], inplace=True)

    df['only_date'] = df['date'].dt.date
    df['year'] = df['date'].dt.year
    df['month_num'] = df['date'].dt.month
    df['month'] = df['date'].dt.month_name()
    df['day'] = df['date'].dt.day
    df['day_name'] = df['date'].dt.day_name()
    df['hour'] = df['date'].dt.hour
    df['minute'] = df['date'].dt.minute

    period = []
    for hour in df[['day_name', 'hour']]['hour']:
        if hour == 23:
            period.append(str(hour) + "-" + str('00'))
        elif hour == 0:
            period.append(str('00') + "-" + str(hour + 1))
        else:
            period.append(str(hour) + "-" + str(hour + 1))

    df['period'] = period

    return df