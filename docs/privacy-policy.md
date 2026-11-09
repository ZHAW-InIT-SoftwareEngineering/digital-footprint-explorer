# Digital Footprint Explorer

## Privacy policy

Last updated: 8 November 2026

Digital Footprint Explorer helps you understand an estimated carbon footprint of your device use. Your settings, calculations and history are processed on your device. You do not need an app account.

The DFE Team maintains the Digital Footprint Explorer iOS app within School of Engineering ZHAW and handles privacy and support questions.

### What the app uses

The app keeps daily category times and the calculation settings used for them. These settings include estimated data traffic, Wi-Fi share, screen brightness, GPS time and Bluetooth time. The current interface uses starting model assumptions and does not ask you to type daily inputs.

The app does not measure your network traffic, physical energy use or location. It does not read your messages, contacts, photos, passwords or the content you view in other apps.

### Your Screen Time choice

The app asks for Screen Time access only when you choose Enable automatic estimates and approve Apple's permission screen. If Apple grants expanded data access, automatic input starts without a second setup form or individual app choices. If access is unavailable or declined, new days stay pending.

When Apple allows data access, the app uses app usage durations for completed days on this device. It matches app identifiers against a small set of local category rules. Apps without a rule stay under Other apps. This classification is an estimate of an app's purpose; it does not identify what you did inside it. The saved history contains category totals, not a list of individual apps, their identifiers or their names.

To avoid counting an app twice and to apply its category rule, the app briefly reads Apple's installed-app list on your device. This lookup stays in memory. The list, names and individual app records are not saved or shared. No app identifiers are sent to an online service for classification.

Website records and browsing details are not used or saved. Time spent in a browser can be included as app use, without reading the websites you visited.

Earlier versions may keep a selection of apps or groups. That narrower setup stays in place until you choose the new all-app mode. New all-app input begins on the day you enable it and does not backfill earlier days.

Apple restricts customer access to expanded activity data by device, system version and region, including EU device and Apple Account requirements. Development tests in Switzerland use a separate Apple-provided profile; this does not establish access for Swiss customers. Adding iPad or Watch support does not change these rules.

### How the data is used

The app uses these inputs to calculate daily estimates, show your history and compare a day with up to seven earlier days. This comparison changes the garden shown in the app.

Updates can run when you open the app or when iOS gives it time in the background. iOS controls background timing, so a new estimate may not appear straight after midnight. Check the completed date shown with the result; it is not today's running total or Apple's weekly daily average across devices. Screen Time supplies available app usage duration; the other inputs remain estimates. If the source reports screen-on activity but no positive app time is available, that day stays pending rather than becoming zero app use. This check does not establish that every kind of activity was available. App activity returned by Apple can differ from the daily total shown in Screen Time, even for the same date and device. Estimates cover the available app durations, not a verified total of every kind of device activity.

If you turn on the optional Daily garden update, the app schedules a short local morning reminder. It can invite you back even when the app is closed. A reminder does not mean that a new estimate is ready.

### Where your data stays

Your daily history and settings are kept in the app's local storage. The history and widget files use iOS file protection. The app does not upload them to a project server, and it has no separate cloud account or sync service.

Your appearance choice stays in the app's local settings and changes only the display. Garden messages follow the saved estimate and its comparison with earlier days; there is no name, goal or personal profile to fill in.

The optional notification setting and a small schedule and delivery log also stay in local storage. The log keeps delivery dates, scheduled times, local time zone information and, for a result-based message, the saved-day date. These details help prevent repeat notifications; the log does not contain app names, app identifiers or usage times.

The app also keeps small local update checks: the completed-day date, the time a successful save was observed, whether the app was open or in the background, and the app build. It keeps up to 32 completed-day checks. These checks contain no app names, app identifiers, usage amounts or footprint values. A day imported before these checks were added keeps its original import time unknown.

Your device's backup settings may include app data in an Apple or computer backup. Those backups are managed outside this app. You can review and remove them through Apple's backup settings.

### What the widget can show

DFE and its own widget share a protected local summary: the date, total estimate, garden state, estimate source, calculation time and whether the day is complete. With automatic setup enabled, they also share the setup date, time zone, calculation assumptions and up to eight recent totals for the seven-day garden comparison. The widget does not receive your individual app choices, app names or full history.

When Apple permits access, the widget can request the previous completed day's app activity and run the same local calculation without opening DFE. It keeps category totals and their calculation inputs in a protected pending record before updating the garden. DFE adds that record to its private history when it next runs. Up to 32 pending days can wait there; a full or unreadable file stops new saves rather than discarding earlier work. No app identifiers or individual app records are saved in this shared file.

iOS decides when a widget gets another update. The widget can run separately after you remove DFE from multitasking, but this does not guarantee a new estimate at 08:00 or at any fixed interval. Unavailable permission, incomplete activity or a failed update keeps the last valid saved garden and its date.

Anyone who can see your Home Screen may see the widget's summary. You can remove the widget at any time. Removing it does not delete your history in the app.

The optional widget guide can ask iOS whether this app's own widget is configured. This only helps with setup. The status is not saved or sent to the project team, and it does not identify where the widget was placed.

The app checks that its shared garden file can be read back. Each widget size can also keep a small local record of its latest data read. These records contain dates, app build and fixed status words, without the garden value or detailed inputs. A data read does not establish exactly when iOS displayed the widget.

### Your optional Apple Watch companion

Watch sharing is off by default. If you enable Show my garden on Apple Watch on your iPhone, DFE sends the latest saved day, total estimate, garden state, estimate source, calculation time and completion status to your paired Watch through Apple Watch Connectivity. A local installation code and an update number also travel with the summary to keep updates in order and reject delayed updates. It does not send app names, app identifiers, individual app records, usage times or your full history. These details are exchanged only between your paired devices. No project server receives them.

The Watch app and its own complications keep that summary in a protected local file. Anyone who can see your Watch may see the estimate. The Watch displays a phone result; it does not read Screen Time or measure Watch energy use. This companion does not connect to an iPad.

A transfer can wait while the Watch is unavailable. The displayed date and saved time identify the cached result; background delivery is not an exact morning schedule. Turning sharing off, disconnecting Screen Time or deleting entries queues an empty state for the Watch. A Watch that is offline can keep its previous summary until it reconnects. Turning sharing off does not remove Screen Time permission on the phone.

### Optional garden updates

Daily garden update is off by default. If you turn it on in Settings, the app asks for Apple's notification permission. This is separate from Screen Time access. The app does not ask for notification permission when you first open it.

The app schedules one reminder per local day at around 08:00 for the next 30 mornings. iOS can display these saved reminders while DFE is closed, including after you remove it from multitasking. The app renews this schedule when you use it or when iOS gives it background time. If it cannot run for more than 30 days, the saved reminders end until the app can prepare more.

A general reminder invites you to explore your latest saved garden. Its wording varies with the local delivery date, without a personal profile or extra activity collection. It does not say that yesterday's estimate is ready or that your garden has changed. It can still appear when activity is missing, access is unavailable or there was no usable activity. Those cases do not become invented estimates.

Before a saved reminder is due, a fresh import may replace its message with a short summary of a valid, non-zero estimate for yesterday. The app can also update older wording in a known future reminder. Both changes use the same pending reminder and delivery time, rather than adding another. Once that day's reminder may have appeared, a later import does not send a second summary, even if you dismissed the first message.

A result-based message describes the actual saved garden and, when available, its change from an earlier completed day. Neither type includes app names, individual usage times or a carbon value. Tapping either opens Today. A local date log helps limit messages to one in each local delivery day.

Reminders use local calendar dates and times. The app checks the schedule again when it can run after a clock or time zone change. iOS, Focus, Scheduled Summary and notification settings can delay or hide a message, so an exact 08:00 delivery or a message every day is not guaranteed. A message does not prove that Screen Time, the garden or the widgets refreshed. Removing DFE from multitasking normally stops background launches of the main app. Its widget may update separately when iOS allows it; a reminder alone does not prove that this happened.

These are local notifications prepared on your device. They do not use an app server, remote push notifications or a data upload. Depending on your iOS settings, a garden message may appear on the Lock Screen or in Notification Center, where someone who can see your screen may read it.

You can turn Daily garden update off in the app or manage notification permission in device settings. Turning it off in the app cancels this feature's pending messages, but keeps its delivery dates to avoid repeats. Messages already shown in Notification Center remain until you clear them there. Turning notifications off does not disconnect Screen Time or delete your saved estimates. Disconnecting Screen Time leaves the separate reminder choice unchanged; turn Daily garden update off too if you do not want reminders.

### Disconnecting Screen Time

In Settings, choose Disconnect Screen Time to stop new imports and clear the app's saved choices. Your earlier daily estimates are kept so you can still review them. You can also manage the permission in your device settings.

Disconnecting does not erase Apple's own Screen Time records. Deleting data in this app and removing Apple's permission are separate actions.

### Reviewing and deleting your data

You can review saved estimates in History. The current interface does not provide manual entry or correction. Earlier saved entries stay readable. Local history is kept until you choose to delete it; there is no automatic age limit for saved entries.

Choose Delete all entries in Settings to remove the routine, history, saved app choices, pending widget records and shared widget summary. This also resets your appearance choice, turns Daily garden update off, clears its local delivery log and the automatic-update checks and cancels its pending messages. This cannot be undone in the app. Messages already shown in Notification Center are not removed by this reset; you can clear them there.

A small disabled setup marker stays in shared storage so an update that was already running cannot restore deleted data. Disconnecting Screen Time also blocks new widget imports; saved estimates remain available.

Delete all entries does not revoke Apple's Screen Time or notification permission. Use Disconnect Screen Time to remove activity access, and device notification settings to change notification permission.

Deleting entries does not remove files you previously shared, copies held by other people, or older device backups. Removing the app also removes its local app storage; manage existing backups separately.

### Sharing a history file

The current interface does not offer a history export. Screen Time-derived history also remains blocked from export in the storage layer, including after any correction made by an older version.

Earlier versions allowed manual history files to be shared. Deleting local data cannot recall those files or remove copies held by other people.

For support, you can choose Copy update checks inside Connection details. It copies only the small technical checks described above, so you can decide whether to share them. It does not copy your history, activity amounts or garden values, and the app does not send the report automatically.

### Advertising and tracking

The app has no advertising, analytics service or tracking tools. It does not sell your data, send usage history to the project team, or link it to information from other apps. The shared calculation code runs on the device.

If you open an online policy page, an Apple guide linked from History tips, or send an email, your browser or mail provider handles that connection. Those websites and services have their own privacy practices. You can read this copy of the policy in the app without opening a website.

### Understanding the estimates

The results are model estimates for awareness and comparison. They are not measured carbon emissions or a direct reading of device energy use. The garden compares a result with up to seven earlier saved days; green does not establish a small environmental impact in absolute terms.

App categories and category-average traffic rates are assumptions. An app can support several types of activity, so a category rule cannot measure the share of video, messages or calls inside it. The imported durations do not establish all background music listening, call type, video quality or actual network traffic. Website records are excluded. The calculation method is explained in Settings.

Automatic input keeps the calculation settings from your saved routine, including valid zero traffic assumptions. New days use the settings that apply to their date; saved days keep their own settings. Starting automatic input does not silently replace those assumptions or recalculate earlier days with new defaults.

On iPad, the app currently uses the same phone reference model. Its power values have not been calibrated for iPad hardware. It is a reference estimate for comparison, not a measurement of iPad energy use. Each device keeps its own activity and history; phone and tablet activity are not combined.

### Online pages and support email

Opening our public privacy or support page connects your browser to GitHub Pages. GitHub records visitors' IP addresses for security. These website logs are separate from the app's local history. The pages do not receive your Screen Time history or saved estimates.

GitHub explains its hosting practices in its privacy statement: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement.

If you choose to email the DFE Team, your email address and the message you send reach the project team at School of Engineering ZHAW. Your mail provider and ZHAW's mail service handle that message so the team can reply. Email is optional; the app does not automatically attach your usage data or history.

Deleting entries in the app does not delete emails you have sent or the website host's logs. Contact the DFE Team if you have a question about a support message or a privacy request.

### Questions and changes

For privacy or support questions, contact the DFE Team at digital-footprint-explorer.init@zhaw.ch. Please do not send your Screen Time history or other private files.

The DFE Team will update this policy if the app's data practices change. The date above identifies this copy.
