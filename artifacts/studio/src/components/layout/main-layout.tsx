import { Sidebar } from "./sidebar";
import { ThemeProvider } from "../theme-provider";

export function MainLayout({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider defaultTheme="dark" storageKey="app-theme">
      <div className="min-h-screen flex bg-background text-foreground font-mono selection:bg-primary/30">
        <Sidebar />
        <main className="flex-1 flex flex-col overflow-hidden">
          {children}
        </main>
      </div>
    </ThemeProvider>
  );
}
