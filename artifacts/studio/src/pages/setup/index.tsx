import { useState } from "react";
import { CheckCircle2, Circle, Copy, Check, Terminal, Download, Cpu, Box, Play, ExternalLink } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  const handleCopy = () => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  };
  return (
    <button
      onClick={handleCopy}
      className="ml-auto p-1.5 rounded text-muted-foreground hover:text-primary hover:bg-primary/10 transition-colors flex-shrink-0"
      title="Copy"
    >
      {copied ? <Check className="h-3.5 w-3.5 text-green-400" /> : <Copy className="h-3.5 w-3.5" />}
    </button>
  );
}

function CodeBlock({ code, language = "bash" }: { code: string; language?: string }) {
  return (
    <div className="relative group mt-2 rounded border border-border bg-black/60 text-xs font-mono">
      <div className="flex items-center px-3 py-1.5 border-b border-border">
        <span className="text-muted-foreground">{language}</span>
        <CopyButton text={code} />
      </div>
      <pre className="p-3 overflow-x-auto leading-relaxed text-green-300 whitespace-pre-wrap">
        {code}
      </pre>
    </div>
  );
}

function StepCard({
  number,
  title,
  status,
  icon: Icon,
  children,
  badge,
  link,
}: {
  number: number;
  title: string;
  status?: "required" | "optional";
  icon: React.ElementType;
  children: React.ReactNode;
  badge?: string;
  link?: { href: string; label: string };
}) {
  return (
    <Card className="border-border relative overflow-hidden">
      <div className="absolute left-0 top-0 bottom-0 w-0.5 bg-primary/40" />
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-3 text-base">
          <span className="flex items-center justify-center w-7 h-7 rounded-full bg-primary/10 text-primary text-xs font-bold border border-primary/30 flex-shrink-0">
            {number}
          </span>
          <Icon className="h-4 w-4 text-primary flex-shrink-0" />
          <span className="font-bold tracking-wide">{title}</span>
          {status && (
            <Badge
              variant={status === "required" ? "default" : "secondary"}
              className="ml-auto text-xs"
            >
              {status}
            </Badge>
          )}
          {badge && (
            <Badge variant="outline" className="ml-auto text-xs border-green-500/50 text-green-400">
              {badge}
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-sm text-muted-foreground">
        {children}
        {link && (
          <a
            href={link.href}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-primary hover:underline text-xs mt-1"
          >
            <ExternalLink className="h-3 w-3" />
            {link.label}
          </a>
        )}
      </CardContent>
    </Card>
  );
}

function PipelineStep({
  icon: Icon,
  label,
  sub,
  time,
  last,
}: {
  icon: React.ElementType;
  label: string;
  sub: string;
  time: string;
  last?: boolean;
}) {
  return (
    <div className="flex items-start gap-3">
      <div className="flex flex-col items-center">
        <div className="w-8 h-8 rounded-full bg-primary/10 border border-primary/30 flex items-center justify-center flex-shrink-0">
          <Icon className="h-4 w-4 text-primary" />
        </div>
        {!last && <div className="w-px flex-1 bg-border mt-1 min-h-[24px]" />}
      </div>
      <div className="pb-5 flex-1">
        <p className="font-semibold text-foreground text-sm">{label}</p>
        <p className="text-muted-foreground text-xs mt-0.5">{sub}</p>
        <Badge variant="outline" className="mt-1.5 text-xs text-muted-foreground border-border">
          ~{time}
        </Badge>
      </div>
    </div>
  );
}

// Detect the API URL for the copy commands
const API_URL = (() => {
  const domains = (import.meta as Record<string, unknown> & { env: Record<string, string> }).env;
  if (typeof window !== "undefined") {
    return window.location.origin;
  }
  return "https://YOUR-APP.replit.app";
})();

const SETUP_CMD = `bash worker/setup.sh`;

const RUN_CMD = `source worker/.venv/bin/activate

python worker/worker.py \\
  --api-url ${API_URL} \\
  --worker-name "RTX5090-Main" \\
  --gpu-model "NVIDIA GeForce RTX 5090"`;

const BLENDER_PATH_WIN = `# Windows PowerShell — add Blender to PATH
$env:PATH += ";C:\\Program Files\\Blender Foundation\\Blender 4.x"

# Or add permanently via System → Advanced → Environment Variables`;

const BLENDER_PATH_LIN = `# Linux — add Blender to PATH
export PATH=$PATH:/opt/blender-4.x/bin

# Add to ~/.bashrc to make it permanent`;

export default function Setup() {
  const [os, setOs] = useState<"windows" | "linux">("windows");

  return (
    <div className="p-6 space-y-8 max-w-3xl">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Worker Setup Guide</h1>
        <p className="text-muted-foreground mt-1 text-sm">
          Connect your RTX 5090 machine to this pipeline — everything runs locally, 100% free.
        </p>
      </div>

      {/* Pipeline overview */}
      <Card className="border-border bg-card">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-bold uppercase tracking-widest text-muted-foreground">
            Pipeline per job (~2–3 min on RTX 5090)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <PipelineStep
            icon={Box}
            label="Background removal"
            sub="rembg strips the background from product images"
            time="1s"
          />
          <PipelineStep
            icon={Cpu}
            label="Hunyuan3D-2 — 3D generation"
            sub="Tencent's top-quality free model turns the photo into a .glb mesh"
            time="20–30s"
          />
          <PipelineStep
            icon={Box}
            label="Blender scene composition"
            sub="Places the model in a living room / bedroom / garden / balcony / kitchen"
            time="5s"
          />
          <PipelineStep
            icon={Play}
            label="Blender Cycles GPU render"
            sub="Photorealistic 3-second video at 1080p — 128 samples on RTX 5090"
            time="60–120s"
          />
          <PipelineStep
            icon={Terminal}
            label="Upload results"
            sub="Video, thumbnail, and .glb posted back to this web app"
            time="1–5s"
            last
          />
        </CardContent>
      </Card>

      {/* Prerequisites */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold tracking-tight flex items-center gap-2">
          <span className="w-1.5 h-4 bg-primary inline-block" />
          Prerequisites
        </h2>

        <StepCard
          number={1}
          title="NVIDIA CUDA 12.4+"
          status="required"
          icon={Cpu}
          link={{ href: "https://www.nvidia.com/Download/index.aspx", label: "Download NVIDIA Drivers" }}
        >
          <p>Install the latest NVIDIA drivers for your RTX 5090. CUDA 12.4 or newer is required for PyTorch.</p>
          <CodeBlock code={`# Verify your CUDA version\nnvcc --version\nnvidia-smi`} />
        </StepCard>

        <StepCard
          number={2}
          title="Python 3.10 or 3.11"
          status="required"
          icon={Terminal}
          link={{ href: "https://www.python.org/downloads/", label: "Download Python" }}
        >
          <p>Python 3.10 or 3.11 recommended. Python 3.12+ may have compatibility issues with some ML packages.</p>
          <CodeBlock code={`python --version\n# Should print: Python 3.10.x or 3.11.x`} />
        </StepCard>

        <StepCard
          number={3}
          title="Git"
          status="required"
          icon={Terminal}
          link={{ href: "https://git-scm.com/downloads", label: "Download Git" }}
        >
          <p>Needed to clone Hunyuan3D-2 from GitHub during setup.</p>
          <CodeBlock code={`git --version\n# Should print: git version 2.x.x`} />
        </StepCard>

        <StepCard
          number={4}
          title="Blender 4.x"
          status="required"
          icon={Box}
          badge="Must be on PATH"
          link={{ href: "https://www.blender.org/download/", label: "Download Blender" }}
        >
          <p>Blender renders the final scene and video. After installing, add it to your system PATH.</p>

          <div className="flex gap-2 mt-2">
            <button
              onClick={() => setOs("windows")}
              className={cn(
                "px-3 py-1 text-xs rounded border transition-colors",
                os === "windows"
                  ? "border-primary bg-primary/10 text-primary"
                  : "border-border text-muted-foreground hover:border-primary/50"
              )}
            >
              Windows
            </button>
            <button
              onClick={() => setOs("linux")}
              className={cn(
                "px-3 py-1 text-xs rounded border transition-colors",
                os === "linux"
                  ? "border-primary bg-primary/10 text-primary"
                  : "border-border text-muted-foreground hover:border-primary/50"
              )}
            >
              Linux
            </button>
          </div>

          <CodeBlock
            code={os === "windows" ? BLENDER_PATH_WIN : BLENDER_PATH_LIN}
          />
          <CodeBlock code={`# Verify Blender is on PATH\nblender --version`} />
        </StepCard>
      </div>

      {/* Setup */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold tracking-tight flex items-center gap-2">
          <span className="w-1.5 h-4 bg-primary inline-block" />
          One-time Setup
        </h2>

        <Card className="border-border">
          <CardContent className="pt-4 space-y-3 text-sm text-muted-foreground">
            <p>
              Run this once on your RTX 5090 machine. It will automatically install PyTorch with CUDA 12.4,
              clone <strong className="text-foreground">Hunyuan3D-2</strong> from GitHub, and download the model
              weights (~7 GB from HuggingFace).
            </p>
            <CodeBlock code={SETUP_CMD} />
            <div className="grid grid-cols-3 gap-3 mt-3 text-xs">
              {[
                { label: "PyTorch + CUDA", sub: "GPU acceleration" },
                { label: "Hunyuan3D-2 weights", sub: "~7 GB, HuggingFace" },
                { label: "rembg model", sub: "Background removal" },
              ].map(({ label, sub }) => (
                <div key={label} className="flex items-start gap-2 p-2 rounded border border-border bg-muted/20">
                  <CheckCircle2 className="h-3.5 w-3.5 text-green-400 mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-foreground font-medium">{label}</p>
                    <p className="text-muted-foreground">{sub}</p>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Run */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold tracking-tight flex items-center gap-2">
          <span className="w-1.5 h-4 bg-primary inline-block" />
          Start the Worker
        </h2>

        <Card className="border-primary/30 border bg-primary/5">
          <CardContent className="pt-4 space-y-3 text-sm text-muted-foreground">
            <p>
              The API URL below is already set to <strong className="text-foreground">this app</strong>.
              Just copy and run on your local machine.
            </p>
            <CodeBlock code={RUN_CMD} />
            <p className="text-xs">
              Once running, your worker will appear in the{" "}
              <a href="/workers" className="text-primary hover:underline">Workers</a> page and begin
              processing jobs from the{" "}
              <a href="/jobs" className="text-primary hover:underline">Render Queue</a> automatically.
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Performance tuning */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold tracking-tight flex items-center gap-2">
          <span className="w-1.5 h-4 bg-primary inline-block" />
          Performance Estimates (RTX 5090)
        </h2>
        <Card className="border-border">
          <CardContent className="pt-4">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left py-2 font-semibold text-muted-foreground text-xs uppercase tracking-wide">Stage</th>
                  <th className="text-right py-2 font-semibold text-muted-foreground text-xs uppercase tracking-wide">Time</th>
                  <th className="text-right py-2 font-semibold text-muted-foreground text-xs uppercase tracking-wide">VRAM</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {[
                  { stage: "Background removal (rembg)", time: "~1s", vram: "<1 GB" },
                  { stage: "Hunyuan3D-2 (50 steps)", time: "~20–30s", vram: "~8 GB" },
                  { stage: "Blender Cycles 128 smp / 72 frames", time: "~60–120s", vram: "~4 GB" },
                  { stage: "Upload + overhead", time: "~5s", vram: "—" },
                ].map((row) => (
                  <tr key={row.stage} className="hover:bg-muted/20 transition-colors">
                    <td className="py-2.5 text-foreground">{row.stage}</td>
                    <td className="py-2.5 text-right text-muted-foreground font-mono">{row.time}</td>
                    <td className="py-2.5 text-right text-muted-foreground font-mono">{row.vram}</td>
                  </tr>
                ))}
                <tr className="font-semibold">
                  <td className="py-2.5 text-primary">Total per job</td>
                  <td className="py-2.5 text-right text-primary font-mono">~2–3 min</td>
                  <td className="py-2.5 text-right text-muted-foreground font-mono">~12 GB</td>
                </tr>
              </tbody>
            </table>
          </CardContent>
        </Card>
      </div>

      {/* Quality tuning */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold tracking-tight flex items-center gap-2">
          <span className="w-1.5 h-4 bg-primary inline-block" />
          Quality Tuning
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
          {[
            {
              label: "Higher 3D quality",
              desc: "Increase inference steps in worker.py",
              code: "--steps 100  # was 50",
              tradeoff: "2× slower",
            },
            {
              label: "Higher render quality",
              desc: "Increase samples in blender_scenes/*.py",
              code: "scene.cycles.samples = 256  # was 128",
              tradeoff: "2× slower render",
            },
            {
              label: "4K output",
              desc: "Change resolution in blender_scenes/*.py",
              code: "scene.render.resolution_x = 3840\nscene.render.resolution_y = 2160",
              tradeoff: "4× larger file",
            },
            {
              label: "Longer video",
              desc: "Increase frame count in blender_scenes/*.py",
              code: "scene.frame_end = 144  # 6s at 24fps",
              tradeoff: "2× render time",
            },
          ].map(({ label, desc, code, tradeoff }) => (
            <Card key={label} className="border-border">
              <CardContent className="pt-4 space-y-1.5">
                <p className="font-semibold text-foreground">{label}</p>
                <p className="text-xs text-muted-foreground">{desc}</p>
                <CodeBlock code={code} language="python" />
                <p className="text-xs text-muted-foreground/60">Trade-off: {tradeoff}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
