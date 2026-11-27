import type { Metadata } from "next";
// Self-hosted fonts (bundled from npm, no Google Fonts request at runtime)
import "@fontsource/roboto/700.css"; // Brand identity · Bold
import "@fontsource-variable/bricolage-grotesque"; // Headings · SemiBold / Bold
import "@fontsource-variable/public-sans"; // Body · Regular / Medium
import "./globals.css";

export const metadata: Metadata = {
  title: "MineNet",
  description: "Decentralized mineral supply chain and AI-powered marketplace",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
