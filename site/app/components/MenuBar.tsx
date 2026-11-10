"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { BellIcon } from "./Glyph";
import { site } from "../../lib/site";

const links = [
  { href: "/#watches", label: "What it watches" },
  { href: "/#clients", label: "Clients" },
  { href: "/privacy/", label: "Privacy" },
  { href: "/get-started/", label: "Get started" },
];

function formatClock(d: Date) {
  const day = d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
  const time = d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  return `${day} ${time}`;
}

/** The site navigation, built as a macOS menu bar with Desktop Buddy's bell on the right. */
export function MenuBar() {
  const pathname = usePathname();
  const [clock, setClock] = useState<string | null>(null);
  const [waiting, setWaiting] = useState(0);

  useEffect(() => {
    const tick = () => setClock(formatClock(new Date()));
    tick();
    const id = window.setInterval(tick, 15_000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    const onCount = (e: Event) => setWaiting((e as CustomEvent<number>).detail);
    window.addEventListener("db:count", onCount);
    return () => window.removeEventListener("db:count", onCount);
  }, []);

  return (
    <header className="menubar">
      <a className="skip" href="#main">Skip to content</a>
      <nav className="menubar__inner" aria-label="Main">
        <Link href="/" className="menubar__brand">
          <Image src="/shots/app-icon.png" alt="" width={22} height={22} priority />
          <span>{site.name}</span>
        </Link>
        <ul className="menubar__links">
          {links.map((l) => (
            <li key={l.href}>
              <Link href={l.href} aria-current={pathname === l.href ? "page" : undefined}>
                {l.label}
              </Link>
            </li>
          ))}
        </ul>
        <div className="menubar__status">
          <span className="menubar__bell" aria-hidden="true">
            <BellIcon />
            {waiting > 0 && <span className="menubar__badge">{waiting}</span>}
          </span>
          <span className="menubar__clock" aria-hidden="true">{clock ?? " "}</span>
          <a className="btn btn--small" href={site.downloadUrl}>Download</a>
        </div>
      </nav>
    </header>
  );
}
