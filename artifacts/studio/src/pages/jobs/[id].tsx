import { useGetJob, getGetJobQueryKey } from "@workspace/api-client-react";
import { Link, useRoute } from "wouter";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { ArrowLeft, Box, Video, AlertCircle, Clock, Server } from "lucide-react";

export default function JobDetail() {
  const [, params] = useRoute("/jobs/:id");
  const id = params?.id ? parseInt(params.id) : 0;
  
  const { data: job, isLoading } = useGetJob(id, {
    query: { enabled: !!id, queryKey: getGetJobQueryKey(id), refetchInterval: 3000 }
  });

  if (isLoading) {
    return <div className="p-6">Loading job...</div>;
  }

  if (!job) {
    return <div className="p-6">Job not found.</div>;
  }

  const isFailed = job.status === "failed";
  const isCompleted = job.status === "completed";
  const isActive = !isFailed && !isCompleted;

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center gap-4 mb-2">
        <Link href="/jobs">
          <Button variant="outline" size="icon">
            <ArrowLeft className="h-4 w-4" />
          </Button>
        </Link>
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Render Job #{job.id}</h1>
          <p className="text-muted-foreground">
            Product: <Link href={`/products/${job.productId}`} className="text-primary hover:underline">{job.productName}</Link>
          </p>
        </div>
        <div className="ml-auto">
          <Badge 
            variant={isCompleted ? "default" : isFailed ? "destructive" : "secondary"}
            className="text-sm px-3 py-1"
          >
            {job.status.replace("_", " ").toUpperCase()}
          </Badge>
        </div>
      </div>

      {isActive && (
        <Card className="border-primary/50 bg-primary/5">
          <CardContent className="p-6 space-y-4">
            <div className="flex justify-between items-center text-sm font-medium">
              <span className="text-primary">Pipeline Active: {job.stage || job.status}</span>
              <span>{job.progressPct || 0}%</span>
            </div>
            <Progress value={job.progressPct || 0} className="h-2" />
          </CardContent>
        </Card>
      )}

      {isFailed && job.errorMessage && (
        <Card className="border-destructive bg-destructive/10">
          <CardContent className="p-6 flex items-start gap-3 text-destructive">
            <AlertCircle className="h-5 w-5 mt-0.5" />
            <div>
              <h3 className="font-semibold">Job Failed</h3>
              <p className="text-sm opacity-90">{job.errorMessage}</p>
            </div>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Configuration</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <span className="text-muted-foreground block text-xs uppercase tracking-wider mb-1">SCENE</span>
                  <span className="font-medium">{job.sceneType.replace("_", " ")}</span>
                </div>
                <div>
                  <span className="text-muted-foreground block text-xs uppercase tracking-wider mb-1">ANIMAL</span>
                  <span className="font-medium">{job.animalType}</span>
                </div>
                <div>
                  <span className="text-muted-foreground block text-xs uppercase tracking-wider mb-1">PRIORITY</span>
                  <span className="font-medium">{job.priority}</span>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Execution</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div className="flex items-center gap-3">
                <Clock className="h-4 w-4 text-muted-foreground" />
                <div>
                  <span className="text-muted-foreground block text-xs">CREATED</span>
                  <span>{new Date(job.createdAt).toLocaleString()}</span>
                </div>
              </div>
              {job.completedAt && (
                <div className="flex items-center gap-3">
                  <Clock className="h-4 w-4 text-emerald-500" />
                  <div>
                    <span className="text-muted-foreground block text-xs">COMPLETED</span>
                    <span>{new Date(job.completedAt).toLocaleString()}</span>
                  </div>
                </div>
              )}
              {job.workerId && (
                <div className="flex items-center gap-3 border-t border-border pt-4">
                  <Server className="h-4 w-4 text-muted-foreground" />
                  <div>
                    <span className="text-muted-foreground block text-xs">ASSIGNED WORKER</span>
                    <span>Node #{job.workerId}</span>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        <div className="lg:col-span-2">
          <Card className="h-full">
            <CardHeader>
              <CardTitle className="text-lg">Outputs</CardTitle>
              <CardDescription>Generated artifacts from the pipeline</CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* 3D Model Output */}
                <div className="space-y-3">
                  <h3 className="font-medium flex items-center gap-2">
                    <Box className="h-4 w-4 text-muted-foreground" /> 3D Model
                  </h3>
                  {job.modelUrl ? (
                    <div className="aspect-video bg-muted rounded-lg border border-border flex items-center justify-center relative overflow-hidden group">
                      {job.thumbnailUrl ? (
                        <img src={job.thumbnailUrl} alt="3D model thumbnail" className="w-full h-full object-cover" />
                      ) : (
                        <Box className="h-12 w-12 text-muted-foreground opacity-50" />
                      )}
                      <div className="absolute inset-0 bg-background/80 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                        <a href={job.modelUrl} download target="_blank" rel="noreferrer">
                          <Button variant="secondary" size="sm">Download GLB</Button>
                        </a>
                      </div>
                    </div>
                  ) : (
                    <div className="aspect-video bg-muted/50 border border-dashed border-border rounded-lg flex items-center justify-center text-sm text-muted-foreground">
                      {isActive && job.status === "generating_3d" ? "Generating 3D model..." : "Not available"}
                    </div>
                  )}
                </div>

                {/* Video Output */}
                <div className="space-y-3">
                  <h3 className="font-medium flex items-center gap-2">
                    <Video className="h-4 w-4 text-muted-foreground" /> AR Video
                  </h3>
                  {job.videoUrl ? (
                    <div className="aspect-video bg-black rounded-lg overflow-hidden border border-border">
                      <video 
                        src={job.videoUrl} 
                        controls 
                        className="w-full h-full object-contain"
                      />
                    </div>
                  ) : (
                    <div className="aspect-video bg-muted/50 border border-dashed border-border rounded-lg flex items-center justify-center text-sm text-muted-foreground">
                      {isActive && (job.status === "rendering_video" || job.status === "compositing") 
                        ? "Rendering video..." 
                        : "Not available"}
                    </div>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
