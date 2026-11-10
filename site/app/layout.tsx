import type { Metadata, Viewport } from "next";
import { MenuBar } from "./components/MenuBar";
import { Footer } from "./components/Footer";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Desktop Buddy: quiet Mac notifications for Google Workspace and Microsoft 365",
    template: "%s · Desktop Buddy",
  },
  description:
    "A read-only Mac menu bar app that tells you when mail, chats, meetings, tasks and reminders need you. Your data stays on your Mac.",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#eef0f3" },
    { media: "(prefers-color-scheme: dark)", color: "#141517" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-GB">
      <body>
        <MenuBar />
        <main id="main">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
