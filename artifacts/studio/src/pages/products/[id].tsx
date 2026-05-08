import { useGetProduct, useListJobs, getGetProductQueryKey, useAddProductImage } from "@workspace/api-client-react";
import { Link, useRoute } from "wouter";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Image as ImageIcon, ArrowLeft, PlaySquare, Plus, Loader2, X } from "lucide-react";
import { CreateJobDialog } from "@/components/jobs/create-job-dialog";
import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

export default function ProductDetail() {
  const [, params] = useRoute("/products/:id");
  const id = params?.id ? parseInt(params.id) : 0;

  const { data: product, isLoading } = useGetProduct(id, {
    query: { enabled: !!id, queryKey: getGetProductQueryKey(id) }
  });

  const { data: jobs, isLoading: jobsLoading } = useListJobs({ productId: id });

  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  const { mutateAsync: addImage } = useAddProductImage();

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setUploadError(null);

    try {
      const formData = new FormData();
      formData.append("file", file);

      const res = await fetch("/api/uploads", { method: "POST", body: formData });
      if (!res.ok) throw new Error(`Upload failed: ${res.statusText}`);
      const { url } = await res.json();

      await addImage({ id, data: { imageUrl: url } });
      await queryClient.invalidateQueries({ queryKey: getGetProductQueryKey(id) });
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  if (isLoading) {
    return <div className="p-6">Loading product...</div>;
  }

  if (!product) {
    return <div className="p-6">Product not found.</div>;
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center gap-4 mb-2">
        <Link href="/products">
          <Button variant="outline" size="icon">
            <ArrowLeft className="h-4 w-4" />
          </Button>
        </Link>
        <div>
          <h1 className="text-3xl font-bold tracking-tight">{product.name}</h1>
          <p className="text-muted-foreground">{product.category} • {product.material || "Unknown material"}</p>
        </div>
        <div className="ml-auto">
          <CreateJobDialog productId={product.id} productName={product.name} />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Images</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {product.imageUrls.length > 0 ? (
                <div className="grid grid-cols-2 gap-2">
                  {product.imageUrls.map((url, i) => (
                    <div key={i} className="aspect-square bg-muted rounded-md overflow-hidden border border-border">
                      <img src={url} alt={`${product.name} ${i + 1}`} className="w-full h-full object-cover" />
                    </div>
                  ))}
                </div>
              ) : (
                <div className="aspect-square bg-muted rounded-md flex flex-col items-center justify-center text-muted-foreground border border-dashed border-border gap-2">
                  <ImageIcon className="h-8 w-8 opacity-50" />
                  <span className="text-sm">No images</span>
                </div>
              )}

              {uploadError && (
                <div className="flex items-center gap-2 text-sm text-destructive bg-destructive/10 rounded-md px-3 py-2">
                  <span className="flex-1">{uploadError}</span>
                  <button onClick={() => setUploadError(null)}>
                    <X className="h-4 w-4" />
                  </button>
                </div>
              )}

              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="hidden"
                onChange={handleFileChange}
              />
              <Button
                variant="outline"
                className="w-full"
                disabled={uploading}
                onClick={() => fileInputRef.current?.click()}
              >
                {uploading ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Uploading…
                  </>
                ) : (
                  <>
                    <Plus className="h-4 w-4 mr-2" />
                    Add Image
                  </>
                )}
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Details</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm">
              <div>
                <span className="text-muted-foreground block">Description</span>
                <span>{product.description || "No description provided."}</span>
              </div>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <span className="text-muted-foreground block">Length</span>
                  <span>{product.dimensionsL ? `${product.dimensionsL}cm` : "-"}</span>
                </div>
                <div>
                  <span className="text-muted-foreground block">Width</span>
                  <span>{product.dimensionsW ? `${product.dimensionsW}cm` : "-"}</span>
                </div>
                <div>
                  <span className="text-muted-foreground block">Height</span>
                  <span>{product.dimensionsH ? `${product.dimensionsH}cm` : "-"}</span>
                </div>
              </div>
              {product.sourceUrl && (
                <div>
                  <span className="text-muted-foreground block">Source URL</span>
                  <a href={product.sourceUrl} target="_blank" rel="noreferrer" className="text-primary hover:underline truncate block">
                    {product.sourceUrl}
                  </a>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        <div className="lg:col-span-2">
          <Card className="h-full border-border">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <PlaySquare className="h-5 w-5 text-primary" />
                Job History
              </CardTitle>
              <CardDescription>Render pipeline jobs for this product</CardDescription>
            </CardHeader>
            <CardContent>
              {jobsLoading ? (
                <div className="space-y-4">
                  <div className="h-16 bg-muted animate-pulse rounded-md" />
                </div>
              ) : jobs && jobs.length > 0 ? (
                <div className="space-y-3">
                  {jobs.map((job) => (
                    <Link key={job.id} href={`/jobs/${job.id}`}>
                      <div className="border border-border rounded-lg p-4 flex items-center justify-between hover:bg-muted/30 cursor-pointer transition-colors">
                        <div>
                          <div className="font-medium flex items-center gap-2">
                            Job #{job.id}
                            <Badge variant={job.status === "completed" ? "default" : job.status === "failed" ? "destructive" : "secondary"}>
                              {job.status.replace("_", " ")}
                            </Badge>
                          </div>
                          <div className="text-sm text-muted-foreground mt-1">
                            {job.sceneType} • {job.animalType}
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="text-sm font-mono text-muted-foreground">
                            {new Date(job.createdAt).toLocaleDateString()}
                          </div>
                          {job.progressPct !== null && job.progressPct < 100 && (
                            <div className="text-xs text-primary mt-1">{job.progressPct}%</div>
                          )}
                        </div>
                      </div>
                    </Link>
                  ))}
                </div>
              ) : (
                <div className="text-center p-8 border border-dashed border-border rounded-lg text-muted-foreground">
                  <p>No jobs have been run for this product yet.</p>
                  <CreateJobDialog productId={product.id} productName={product.name} />
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
