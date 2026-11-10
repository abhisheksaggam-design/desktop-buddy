"use client";

import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import { Glyph, GlyphKind, SampleClientMark } from "./Glyph";

type GroupId = "client" | "dynamatix" | "reminders";

type Note = {
  id: number;
  group: GroupId;
  kind: GlyphKind;
  source: string;
  from?: string;
  title: string;
  preview: string;
  age: string;
};

const groups: { id: GroupId; name: string }[] = [
  { id: "client", name: "Harrow & Finch" },
  { id: "dynamatix", name: "Dynamatix" },
  { id: "reminders", name: "Reminders" },
];

// Arrival order. Sample people and a sample client, not real ones.
const notes: Note[] = [
  { id: 1, group: "dynamatix", kind: "calendar", source: "Google Calendar", title: "Sprint review in 10 minutes", preview: "Google Meet · 11:00–11:30", age: "now" },
  { id: 2, group: "client", kind: "mail", source: "Gmail", from: "Priya Raman", title: "Signed engagement letter", preview: "Attached, with the two changes we agreed on Tuesday.", age: "2m" },
  { id: 3, group: "client", kind: "chat", source: "Microsoft Teams", from: "Tomás Okafor", title: "Q3 close", preview: "Numbers are in the shared folder when you have a minute.", age: "5m" },
  { id: 4, group: "dynamatix", kind: "tasks", source: "Google Tasks", title: "Send sprint report", preview: "Due today", age: "30m" },
  { id: 5, group: "reminders", kind: "reminder", source: "Reminder", title: "Drink a glass of water", preview: "Every 30 min · weekdays", age: "now" },
];

function GroupMark({ id, size }: { id: GroupId; size: number }) {
  if (id === "client") return <SampleClientMark size={size} />;
  if (id === "reminders") return <Glyph kind="reminder" size={size} />;
  return <Image src="/shots/app-icon.png" alt="" width={size} height={size} className="mark-img" />;
}

export function NotificationDemo() {
  const [arrived, setArrived] = useState(0);
  const [cleared, setCleared] = useState<Set<number>>(new Set());
  const [filter, setFilter] = useState<GroupId | "all">("all");
  const [run, setRun] = useState(0);

  // Notifications arrive one at a time, the way they do on a real morning.
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setArrived(notes.length);
      return;
    }
    setArrived(0);
    const timers = notes.map((_, i) => window.setTimeout(() => setArrived(i + 1), 700 + i * 900));
    return () => timers.forEach(window.clearTimeout);
  }, [run]);

  const visible = useMemo(
    () => notes.slice(0, arrived).filter((n) => !cleared.has(n.id)),
    [arrived, cleared],
  );

  useEffect(() => {
    window.dispatchEvent(new CustomEvent("db:count", { detail: visible.length }));
  }, [visible.length]);

  const countFor = (g: GroupId) => visible.filter((n) => n.group === g).length;
  const clear = (ids: number[]) => setCleared((prev) => new Set([...prev, ...ids]));
  const shown = filter === "all" ? visible : visible.filter((n) => n.group === filter);
  const replay = () => {
    setCleared(new Set());
    setFilter("all");
    setRun((r) => r + 1);
  };

  return (
    <div className="demo">
      <section className="panel" aria-label="Sample notifications">
        <div className="panel__head">
          <h2 className="panel__title">Notifications</h2>
          {visible.length > 0 && (
            <button className="panel__textbtn" onClick={() => clear(visible.map((n) => n.id))}>
              Clear All
            </button>
          )}
        </div>

        <div className="chips" role="group" aria-label="Show notifications for">
          <button className="chip" aria-pressed={filter === "all"} onClick={() => setFilter("all")}>
            All <span className="chip__n">{visible.length}</span>
          </button>
          {groups.map((g) =>
            countFor(g.id) > 0 ? (
              <button key={g.id} className="chip" aria-pressed={filter === g.id} onClick={() => setFilter(g.id)}>
                <GroupMark id={g.id} size={18} />
                <span className="sr-only">{g.name}</span>
                <span className="chip__n">{countFor(g.id)}</span>
              </button>
            ) : null,
          )}
        </div>

        <div className="panel__body" aria-live="polite">
          {shown.length === 0 && (
            <div className="panel__empty">
              <p>{arrived < notes.length && cleared.size === 0 ? "Watching your accounts…" : "Nothing waiting. Enjoy the quiet."}</p>
              {cleared.size > 0 && (
                <button className="panel__textbtn" onClick={replay}>Play it again</button>
              )}
            </div>
          )}
          {groups.map((g) => {
            const items = shown.filter((n) => n.group === g.id);
            if (items.length === 0) return null;
            return (
              <div key={g.id} className="group">
                <div className="group__head">
                  <span>{g.name}</span>
                  <button className="panel__textbtn" onClick={() => clear(items.map((n) => n.id))}>
                    Clear<span className="sr-only"> {g.name}</span>
                  </button>
                </div>
                {items.map((n) => (
                  <article key={`${run}-${n.id}`} className="note">
                    <Glyph kind={n.kind} size={36} />
                    <div className="note__text">
                      <div className="note__meta">
                        <span>{n.from ?? n.source}</span>
                        <span className="note__age">{n.age}</span>
                      </div>
                      <h3 className="note__title">{n.title}</h3>
                      <p className="note__preview">{n.preview}</p>
                    </div>
                  </article>
                ))}
              </div>
            );
          })}
        </div>
      </section>

      <div className="dock" aria-hidden="true">
        {groups.map((g) => (
          <div key={g.id} className="dock__item" data-on={countFor(g.id) > 0}>
            <span className="dock__tile">
              <GroupMark id={g.id} size={44} />
              {countFor(g.id) > 0 && <span className="dock__badge">{countFor(g.id)}</span>}
            </span>
            <span className="dock__label">{g.name}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
