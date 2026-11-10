import Image from "next/image";
import Link from "next/link";
import { Glyph, GlyphKind } from "./components/Glyph";
import { NotificationDemo } from "./components/NotificationDemo";
import { site } from "../lib/site";

const watches: { kind: GlyphKind; name: string; services: string; body: string }[] = [
  {
    kind: "mail",
    name: "Mail",
    services: "Gmail · Outlook",
    body: "New unread mail in your inbox. Mail you've already read or filed away never interrupts you.",
  },
  {
    kind: "chat",
    name: "Chat messages",
    services: "Google Chat · Microsoft Teams",
    body: "New messages in your chats and spaces, with the sender's name and the message. They stay until you clear them.",
  },
  {
    kind: "calendar",
    name: "Meetings starting soon",
    services: "Google Calendar · Outlook",
    body: "A heads-up before each meeting: 2, 5, 10 or 15 minutes before. Ten is the default.",
  },
  {
    kind: "tasks",
    name: "Tasks due today",
    services: "Google Tasks · Microsoft To Do",
    body: "Anything due today, plus anything overdue, so nothing slips past yesterday.",
  },
  {
    kind: "reminder",
    name: "Your own reminders",
    services: "On your Mac, no account needed",
    body: "Drink water every 30 minutes on weekdays, stand up at 3pm. They work offline.",
  },
];

const clientRules = [
  { name: "Senders", body: "A whole domain like client.com, or one person." },
  { name: "Keywords", body: "A whole word in the subject or preview, so “FEMA” won't match “female”." },
  { name: "Chats", body: "Google Chat spaces or Teams chats you pick from a list." },
  { name: "Name match", body: "Any chat whose name includes the client's name." },
];

const settings = [
  { term: "Check accounts every", value: "1 minute" },
  { term: "Warn about meetings", value: "10 minutes before" },
  { term: "Quiet hours", value: "Nothing pops up; it waits for you" },
  { term: "Pause all", value: "One switch, every account" },
  { term: "Open at login", value: "Optional" },
];

export default function Home() {
  return (
    <>
      <section className="hero">
        <div className="wrap hero__grid">
          <div className="hero__copy">
            <p className="hero__kicker">For Mac · Google Workspace and Microsoft 365</p>
            <h1 className="hero__title">A quiet tap on the shoulder when work needs you.</h1>
            <p className="hero__lede">
              Desktop Buddy sits in your menu bar and shows a small notification on your desktop for new mail,
              chat messages, meetings about to start and tasks due today. Then it gets out of the way.
            </p>
            <div className="hero__actions">
              <a className="btn btn--onblue" href={site.downloadUrl}>Download for Mac</a>
              <Link className="hero__link" href="/get-started/">How to install</Link>
            </div>
            <p className="hero__fine">
              Version {site.version} · {site.minOS} · Apple silicon and Intel
            </p>
          </div>
          <NotificationDemo />
        </div>
      </section>

      <section className="section" id="watches" aria-labelledby="watches-title">
        <div className="wrap split">
          <div className="split__aside">
            <h2 id="watches-title" className="h2">Five things it watches, so you don't have to.</h2>
            <p className="muted">
              One sign-in per account covers all of them. Turn any of them off, per account, in Settings.
            </p>
          </div>
          <ul className="rows">
            {watches.map((w) => (
              <li key={w.name} className="row">
                <Glyph kind={w.kind} size={40} />
                <div>
                  <h3 className="row__title">
                    {w.name} <span className="row__services">{w.services}</span>
                  </h3>
                  <p className="row__body">{w.body}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="section section--tint" id="clients" aria-labelledby="clients-title">
        <div className="wrap">
          <div className="clients__intro">
            <h2 id="clients-title" className="h2">Every client under their own logo.</h2>
            <p className="lede">
              Work for several clients? Make each one a Client. Their mail and chats gather under their logo on your
              desktop, even if they never gave you an account. You see who needs you before you read a word.
            </p>
          </div>
          <div className="clients__body">
            <figure className="shot shot--wide">
              <Image
                src="/shots/settings-client.png"
                alt="The Client settings page, with a sender domain and two keywords added."
                width={1680}
                height={1240}
                sizes="(max-width: 900px) 100vw, 60vw"
              />
            </figure>
            <dl className="rules">
              {clientRules.map((r) => (
                <div key={r.name} className="rules__item">
                  <dt>{r.name}</dt>
                  <dd>{r.body}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </section>

      <section className="section" aria-labelledby="menubar-title">
        <div className="wrap menubar-feature">
          <figure className="shot shot--popover">
            <Image
              src="/shots/popover.png"
              alt="The Desktop Buddy menu bar window, listing six waiting notifications grouped by account and client."
              width={720}
              height={1040}
              sizes="(max-width: 900px) 80vw, 360px"
            />
          </figure>
          <div>
            <h2 id="menubar-title" className="h2">Everything waiting, one click away.</h2>
            <p className="lede">
              Click the bell in your menu bar to see what's waiting, turn an account off for the afternoon, or clear the lot.
            </p>
            <dl className="spec">
              {settings.map((s) => (
                <div key={s.term} className="spec__row">
                  <dt>{s.term}</dt>
                  <dd>{s.value}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </section>

      <section className="section section--ink" aria-labelledby="privacy-title">
        <div className="wrap privacy">
          <h2 id="privacy-title" className="h2 privacy__title">
            It can look. It can't touch.
          </h2>
          <p className="privacy__lede">
            Desktop Buddy only asks for read-only access, and your Mac talks straight to Google and Microsoft.
            There are no Desktop Buddy servers for your data to go to.
          </p>
          <div className="privacy__cols">
            <div>
              <h3 className="privacy__h">What it reads</h3>
              <ul className="ticks">
                <li>Unread inbox mail: sender, subject and a short preview</li>
                <li>New chat messages, with who sent them</li>
                <li>Your calendar, to warn you before meetings</li>
                <li>Tasks due today</li>
                <li>Colleagues' names, so chats show a name, not an ID</li>
              </ul>
            </div>
            <div>
              <h3 className="privacy__h">What it never does</h3>
              <ul className="crosses">
                <li>Send, change or delete anything</li>
                <li>See or store your password</li>
                <li>Send your data to us or anyone else</li>
                <li>Use AI, analytics or ads</li>
              </ul>
            </div>
          </div>
          <p className="privacy__foot">
            Sign-ins live in your Mac's Keychain. <Link href="/privacy/">Read the full privacy notice</Link>
          </p>
        </div>
      </section>

      <section className="section" aria-labelledby="start-title">
        <div className="wrap start">
          <h2 id="start-title" className="h2">Up and running in about two minutes.</h2>
          <ol className="steps">
            <li>
              <h3>Download and drag it to Applications</h3>
              <p>Open the DMG and drag Desktop Buddy into Applications.</p>
            </li>
            <li>
              <h3>Allow it the first time</h3>
              <p>
                macOS asks before opening apps from outside the App Store. Open System Settings, Privacy &amp; Security,
                and click Open Anyway. You only do this once.
              </p>
            </li>
            <li>
              <h3>Sign in with Google or Microsoft</h3>
              <p>Your browser opens, you pick the account and click Allow. A bell appears in your menu bar.</p>
            </li>
          </ol>
          <div className="start__actions">
            <a className="btn" href={site.downloadUrl}>Download for Mac</a>
            <Link className="textlink" href="/get-started/">Step-by-step guide</Link>
          </div>
        </div>
      </section>
    </>
  );
}
