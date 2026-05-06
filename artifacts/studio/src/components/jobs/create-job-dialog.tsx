import { useState } from "react";
import { useCreateJob } from "@workspace/api-client-react";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useToast } from "@/hooks/use-toast";
import { PlaySquare } from "lucide-react";

export function CreateJobDialog({ productId, productName }: { productId: number, productName?: string }) {
  const [open, setOpen] = useState(false);
  const [sceneType, setSceneType] = useState<string>("living_room");
  const [animalType, setAnimalType] = useState<string>("cat");
  
  const createJob = useCreateJob();
  const { toast } = useToast();
  const [, setLocation] = useLocation();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    createJob.mutate({
      data: {
        productId,
        sceneType: sceneType as any,
        animalType: animalType as any,
        priority: 1
      }
    }, {
      onSuccess: (job) => {
        toast({
          title: "Job Created",
          description: `Render job for ${productName || 'product'} has been queued.`,
        });
        setOpen(false);
        setLocation(`/jobs/${job.id}`);
      },
      onError: (err) => {
        toast({
          title: "Error",
          description: "Failed to create render job.",
          variant: "destructive"
        });
      }
    });
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button className="mt-4">
          <PlaySquare className="h-4 w-4 mr-2" />
          Start Render Job
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>New Render Job</DialogTitle>
            <DialogDescription>
              Queue a new pipeline job for {productName || "this product"}.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid gap-2">
              <Label htmlFor="sceneType">Scene Setting</Label>
              <Select value={sceneType} onValueChange={setSceneType}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a scene" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="living_room">Living Room</SelectItem>
                  <SelectItem value="bedroom">Bedroom</SelectItem>
                  <SelectItem value="balcony">Balcony</SelectItem>
                  <SelectItem value="garden">Garden</SelectItem>
                  <SelectItem value="kitchen">Kitchen</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="animalType">Pet Companion</Label>
              <Select value={animalType} onValueChange={setAnimalType}>
                <SelectTrigger>
                  <SelectValue placeholder="Select a pet" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="cat">Cat</SelectItem>
                  <SelectItem value="dog">Dog</SelectItem>
                  <SelectItem value="none">None (Product Only)</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={createJob.isPending}>
              {createJob.isPending ? "Starting..." : "Start Pipeline"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
