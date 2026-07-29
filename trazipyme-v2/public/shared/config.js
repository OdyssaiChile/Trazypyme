// Config compartida — TraziPyme (proyecto Supabase: trazipyme-prod)
window.TRAZI_CONFIG = {
  SUPABASE_URL: "https://kqqhbhrovrqpqttlksmz.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxcWhiaHJvdnJxcHF0dGxrc216Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyNTg4MjAsImV4cCI6MjEwMDgzNDgyMH0.v810avsAjNrkbgxETYqKMFx8y6ipiV7bLoe7kE6epY4",
  get FUNCTIONS_URL() { return this.SUPABASE_URL + "/functions/v1"; }
};
