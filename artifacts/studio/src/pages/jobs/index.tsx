import { useListJobs } from "@workspace/api-client-react";
import { Link } from "wouter";
import { Badge } from "@/components/ui/badge";

export default function Jobs() {
  const { data: jobs, isLoading } = useListJobs();

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold tracking-tight">Render Queue</h1>
      </div>

      <div className="rounded-md border border-border bg-card">
        {isLoading ? (
          <div className="p-8 text-center text-muted-foreground">Loading queue...</div>
        ) : jobs && jobs.length > 0 ? (
          <div className="divide-y divide-border">
            {jobs.map((job) => (
              <Link key={job.id} href={`/jobs/${job.id}`}>
                <div className="flex items-center justify-between p-4 hover:bg-muted/50 cursor-pointer transition-colors">
                  <div>
                    <h3 className="font-medium">{job.productName}</h3>
                    <p className="text-sm text-muted-foreground">
                      {job.sceneType} • {job.animalType}
                    </p>
                  </div>
                  <div className="flex items-center gap-4">
                    <Badge variant={job.status === "completed" ? "default" : job.status === "failed" ? "destructive" : "secondary"}>
                      {job.status}
                    </Badge>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <div className="p-8 text-center text-muted-foreground">No jobs in queue.</div>
        )}
      </div>
    </div>
  );
}
