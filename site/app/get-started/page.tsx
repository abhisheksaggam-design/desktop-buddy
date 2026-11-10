import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { site } from "../../lib/site";

export const metadata: Metadata = {
  title: "Get started",
  description: "Install Desktop Buddy, open it the first time, and sign in with Google or Microsoft.",
};

export default function GetStarted() {
  return (
    <article className="doc">
      <p className="doc__kicker">Get started</p>
      <h1>Install Desktop Buddy</h1>
      <p className="doc__lede">
        It takes about two minutes. You need a Mac running {site.minOS}, with Apple silicon or Intel.
      </p>

      <h2>1. Download it</h2>
      <ol>
        <li>
          Download <strong>Desktop-Buddy.dmg</strong> from the <a href={site.downloadUrl}>latest release</a>.
        </li>
        <li>Open the DMG and drag <strong>Desktop Buddy</strong> into <strong>Applications</strong>.</li>
        <li>Open Desktop Buddy from Applications.</li>
      </ol>

      <h2>2. Allow it the first time</h2>
      <p>
        Desktop Buddy isn't notarised by Apple yet, so the first time you open it macOS says “Apple could not verify”
        it. That's expected.
      </p>
      <ol>
        <li>Click <strong>Done</strong> on the warning.</li>
        <li>Open <strong>System Settings</strong>, then <strong>Privacy &amp; Security</strong>.</li>
        <li>Scroll down to the message about Desktop Buddy and click <strong>Open Anyway</strong>.</li>
        <li>Enter your Mac password and click <strong>Open</strong>.</li>
      </ol>
      <p>You only do this once. When it's running, a bell appears in your menu bar and Settings opens.</p>

      <h2>3. Sign in</h2>
      <ol>
        <li>In Settings, click <strong>Sign in with Google</strong> or <strong>Sign in with Microsoft</strong>.</li>
        <li>Your browser opens. Choose the account you want and click <strong>Allow</strong>.</li>
        <li>
          That's it. Desktop Buddy names the account from your email address, so <code>you@dynamatix.co.uk</code>{" "}
          becomes <strong>Dynamatix</strong>, with its logo. You can rename it.
        </li>
      </ol>
      <p>
        One sign-in covers mail, chats, meetings and tasks. To add another account later, use{" "}
        <strong>Add Account…</strong> in the sidebar.
      </p>
      <figure className="shot">
        <Image
          src="/shots/settings-account.png"
          alt="An account page in Desktop Buddy Settings, with switches for mail, chats, meetings and tasks."
          width={1680}
          height={1240}
          sizes="(max-width: 800px) 100vw, 760px"
        />
      </figure>

      <div className="callout">
        <p>
          <strong>Keychain asks for permission?</strong> The first time the app reads your saved sign-ins, macOS asks.
          Enter your Mac password and click <strong>Always Allow</strong>.
        </p>
        <p>
          <strong>Wrong browser profile?</strong> While it waits, click <strong>Copy Sign-in Link</strong> and paste
          the link into the browser profile you use for that account.
        </p>
      </div>

      <h2>4. Make it yours</h2>
      <ul>
        <li><strong>Clients:</strong> group a client's mail and chats under their logo. Click <strong>Add Client…</strong> in the sidebar.</li>
        <li><strong>Reminders:</strong> add your own, like a glass of water every 30 minutes on weekdays.</li>
        <li><strong>Quiet hours:</strong> nothing pops up, and anything that arrives waits until they end.</li>
        <li><strong>Size and position:</strong> drag the notifications anywhere, and make them bigger or smaller.</li>
      </ul>

      <h2>Updating</h2>
      <p>
        Once a day Desktop Buddy checks for a new version. When there is one, the menu bar window shows a{" "}
        <strong>Download</strong> button. Drag the new version into Applications and choose <strong>Replace</strong>.
        Your accounts and settings stay.
      </p>

      <h2>Removing it</h2>
      <p>
        Quit it, move it to the Bin, and delete its data folder. The <Link href="/privacy/#removing">privacy notice</Link>{" "}
        has the exact steps.
      </p>

      <h2>Need help?</h2>
      <p>
        Email <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>.
      </p>
    </article>
  );
}
