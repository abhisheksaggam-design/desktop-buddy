import type { Metadata } from "next";
import { site } from "../../lib/site";

export const metadata: Metadata = {
  title: "Privacy notice",
  description: "What Desktop Buddy reads from your Google and Microsoft accounts, where it keeps it, and who it shares it with: no one.",
};

const google = [
  ["openid, email", "Your email address, to name the account in Settings."],
  ["gmail.readonly", "Unread inbox mail: sender, subject and a short preview."],
  ["calendar.readonly", "Meetings starting soon, so it can warn you before they start."],
  ["chat.spaces.readonly", "The list of your Google Chat spaces, so you can pick them for a Client."],
  ["chat.messages.readonly", "New chat messages: who sent them and the text."],
  ["tasks.readonly", "Tasks due today or overdue."],
  ["directory.readonly", "Colleagues' names, so chats show a person's name instead of an ID."],
];

const microsoft = [
  ["User.Read", "Your name and email address, to name the account in Settings."],
  ["Mail.Read", "Unread inbox mail: sender, subject and a short preview."],
  ["Calendars.Read", "Meetings starting soon."],
  ["Chat.Read", "New Teams chat messages."],
  ["Tasks.Read", "Microsoft To Do tasks due today or overdue."],
  ["offline_access", "Lets it keep checking without asking you to sign in every hour."],
];

export default function Privacy() {
  return (
    <article className="doc">
      <p className="doc__kicker">Desktop Buddy</p>
      <h1>Privacy notice</h1>
      <p className="doc__lede">
        Desktop Buddy is a Mac app that shows you notifications from your own Google Workspace and Microsoft 365
        accounts. It reads a small amount of your data to do that, keeps it on your Mac, and never sends it to us or
        anyone else.
      </p>
      <p className="doc__meta">Last updated 27 October 2026</p>

      <h2>Who we are</h2>
      <p>
        Desktop Buddy is published by {site.publisher}, a company registered in England and Wales (company number
        08575927). This notice covers the Desktop Buddy app. Our{" "}
        <a href={site.companyPrivacyUrl}>company privacy policy</a> covers the Dynamatix website and our other services.
      </p>

      <h2>The short version</h2>
      <ul>
        <li>Desktop Buddy only reads. It never sends, changes or deletes anything in your accounts.</li>
        <li>Your Mac talks directly to Google and Microsoft. There are no Desktop Buddy servers.</li>
        <li>We don't collect, see, sell or share your data. We have no analytics, no ads and no AI.</li>
        <li>You can remove its access at any time.</li>
      </ul>

      <h2>What it reads from Google</h2>
      <p>When you sign in with Google, Desktop Buddy asks for these read-only permissions:</p>
      <table className="table">
        <thead><tr><th scope="col">Permission</th><th scope="col">What it's used for</th></tr></thead>
        <tbody>
          {google.map(([scope, use]) => (
            <tr key={scope}><td><code>{scope}</code></td><td>{use}</td></tr>
          ))}
        </tbody>
      </table>

      <h2>What it reads from Microsoft</h2>
      <table className="table">
        <thead><tr><th scope="col">Permission</th><th scope="col">What it's used for</th></tr></thead>
        <tbody>
          {microsoft.map(([scope, use]) => (
            <tr key={scope}><td><code>{scope}</code></td><td>{use}</td></tr>
          ))}
        </tbody>
      </table>

      <h2>How it uses your data</h2>
      <p>
        Only to show you your own notifications on your own Mac. Nothing else. Your data is not used for advertising,
        not used to train AI or machine-learning models, and not read by any person at Dynamatix.
      </p>

      <h2>Where your data is kept</h2>
      <ul>
        <li>
          <strong>Sign-in tokens</strong> are stored in your Mac's Keychain. Sign-in happens in your own browser using
          OAuth 2.0 with PKCE, so Desktop Buddy never sees your password.
        </li>
        <li>
          <strong>Settings and the notifications currently on screen</strong> (sender, subject and a short preview) are
          stored in <code>~/Library/Application Support/DesktopBuddyV2/</code> on your Mac. A notification is removed
          when you clear it, or when the email is read or the task is done.
        </li>
        <li>
          <strong>A local log</strong> in the same folder records counts and errors only, never message content. It's
          capped at 1 MB.
        </li>
      </ul>

      <h2>Who it's shared with</h2>
      <p>
        No one. Desktop Buddy connects only to Google's and Microsoft's own services over HTTPS. Once a day it also
        checks GitHub for a newer version of the app; that check sends no account data, and you can turn it off in
        Settings.
      </p>

      <h2>Google API Services User Data Policy</h2>
      <p>
        Desktop Buddy's use and transfer of information received from Google APIs adheres to the{" "}
        <a href="https://developers.google.com/terms/api-services-user-data-policy">Google API Services User Data Policy</a>,
        including the Limited Use requirements. Data from Google is used only to show you your own notifications. It
        is not transferred to anyone, not sold, not used for advertising and not used to train AI models.
      </p>

      <h2 id="removing">Removing your data</h2>
      <ol>
        <li>Quit Desktop Buddy and move it from Applications to the Bin.</li>
        <li>Delete the folder <code>~/Library/Application Support/DesktopBuddyV2/</code>.</li>
        <li>In Keychain Access, delete the item named <code>com.desktopbuddy.v2</code>.</li>
        <li>
          Optionally, remove its access from your account: <a href="https://myaccount.google.com/connections">Google
          account connections</a> or <a href="https://myapps.microsoft.com">Microsoft My Apps</a>.
        </li>
      </ol>
      <p>Because we never hold a copy of your data, there is nothing for us to delete on our side.</p>

      <h2>Changes to this notice</h2>
      <p>If we change what Desktop Buddy reads or how it uses it, we'll update this page and the date at the top.</p>

      <h2>Contact</h2>
      <p>
        Questions about this notice or your data: <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>,
        or write to {site.publisher}, Suite 2-9, Margaret Powell House, 401–447 Midsummer Boulevard, Central Milton
        Keynes, MK9 3BN, United Kingdom.
      </p>
    </article>
  );
}
