import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.Function;
import java.nio.file.*;
public class RecoverFollowup extends GhidraScript {
 public void run() throws Exception {
  DecompInterface d = new DecompInterface();
  DecompileOptions o = new DecompileOptions();
  o.grabFromProgram(currentProgram); o.setMaxPayloadMBytes(200);
  d.setOptions(o); d.openProgram(currentProgram);
  Function f = getFunctionAt(toAddr("1020d6744"));
  println("RECOVER function=" + f);
  DecompileResults r = d.decompileFunction(f, 240, monitor);
  if (!r.decompileCompleted()) throw new Exception(r.getErrorMessage());
  Files.writeString(Path.of("/tmp/codex-heyclicky/followup-1020d6744.c"), r.getDecompiledFunction().getC());
  println("RECOVER complete"); d.dispose();
 }
}
