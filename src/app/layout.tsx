import type { Metadata } from "next";
import "./globals.css";

const TITLE = process.env.NEXT_PUBLIC_TITLE || "Proxmox Wallboard";

export const metadata: Metadata = {
  title: TITLE,
  description: "Homelab monitoring wallboard for Proxmox VE",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
