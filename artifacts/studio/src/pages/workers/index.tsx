import { useListWorkers, useRegisterWorker } from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Plus, Cpu } from "lucide-react";
import { useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { useQueryClient } from "@tanstack/react-query";

function RegisterWorkerDialog() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [gpuModel, setGpuModel] = useState("");
  
  const registerWorker = useRegisterWorker();
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name) return;

    registerWorker.mutate({
      data: {
        name,
        gpuModel: gpuModel || undefined
      }
    }, {
      onSuccess: () => {
        toast({
          title: "Worker Registered",
          description: `Worker node "${name}" has been registered successfully.`,
        });
        setOpen(false);
        setName("");
        setGpuModel("");
        queryClient.invalidateQueries({ queryKey: ["/api/workers"] });
      },
      onError: () => {
        toast({
          title: "Registration Failed",
          description: "Could not register the worker node.",
          variant: "destructive"
        });
      }
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="h-4 w-4 mr-2" />
          Register Worker
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Register Worker Node</DialogTitle>
            <DialogDescription>
              Add a new GPU workstation to the rendering pipeline cluster.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <Label htmlFor="name">Node Name</Label>
              <Input 
                id="name" 
                value={name} 
                onChange={(e) => setName(e.target.value)} 
                placeholder="e.g., render-node-01" 
                required 
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="gpuModel">GPU Model (Optional)</Label>
              <Input 
                id="gpuModel" 
                value={gpuModel} 
                onChange={(e) => setGpuModel(e.target.value)} 
                placeholder="e.g., RTX 5090" 
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={registerWorker.isPending || !name}>
              {registerWorker.isPending ? "Registering..." : "Register"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export default function Workers() {
  const { data: workers, isLoading } = useListWorkers();

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold tracking-tight">Worker Nodes</h1>
        <RegisterWorkerDialog />
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <Card key={i} className="animate-pulse h-32 bg-muted" />
          ))}
        </div>
      ) : workers && workers.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {workers.map((worker) => (
            <Card key={worker.id} className="border-border">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-base font-bold flex items-center gap-2">
                  <Cpu className="h-4 w-4" />
                  {worker.name}
                </CardTitle>
                <Badge variant={worker.status === "online" ? "default" : worker.status === "busy" ? "secondary" : "destructive"}>
                  {worker.status}
                </Badge>
              </CardHeader>
              <CardContent>
                <div className="text-sm text-muted-foreground mt-2">
                  <p>GPU: {worker.gpuModel || "Unknown"}</p>
                  <p>Jobs Completed: {worker.jobsCompleted}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <div className="p-8 text-center text-muted-foreground border border-dashed border-border rounded-lg bg-card">
          No workers registered.
        </div>
      )}
    </div>
  );
}
