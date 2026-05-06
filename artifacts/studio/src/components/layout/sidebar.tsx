import { Link, useLocation } from "wouter";
import { LayoutDashboard, Package, PlaySquare, Server, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

const links = [
  { href: "/", label: "Dashboard", icon: LayoutDashboard },
  { href: "/products", label: "Products", icon: Package },
  { href: "/jobs", label: "Render Queue", icon: PlaySquare },
  { href: "/workers", label: "Workers", icon: Server },
];

export function Sidebar() {
  const [location] = useLocation();

  return (
    <aside className="w-64 flex flex-col border-r border-border bg-sidebar text-sidebar-foreground">
      <div className="h-16 flex items-center px-6 border-b border-border">
        <span className="font-mono font-bold tracking-tight text-primary flex items-center gap-2">
          <div className="w-3 h-3 bg-primary" />
          3D STUDIO
        </span>
      </div>
      
      <nav className="flex-1 py-6 px-4 space-y-1">
        {links.map((link) => {
          const active = location === link.href || (link.href !== "/" && location.startsWith(link.href));
          return (
            <Link
              key={link.href}
              href={link.href}
              className={cn(
                "flex items-center gap-3 px-3 py-2 text-sm font-medium transition-colors hover:text-primary",
                active 
                  ? "text-primary bg-primary/10" 
                  : "text-muted-foreground hover:bg-muted"
              )}
            >
              <link.icon className="h-4 w-4" />
              {link.label}
            </Link>
          );
        })}
      </nav>

      <div className="p-4 border-t border-border">
        <button className="flex items-center gap-3 px-3 py-2 w-full text-sm font-medium text-muted-foreground hover:text-primary hover:bg-muted transition-colors">
          <Settings className="h-4 w-4" />
          Settings
        </button>
      </div>
    </aside>
  );
}
