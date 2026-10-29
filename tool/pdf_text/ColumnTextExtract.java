// Host-side mirror of android/.../ColumnTextStripper.kt, on desktop Apache
// PDFBox 2.0.27 (the same text-stripper code pdfbox-android 2.0.27 ports).
// It prints a PDF's text exactly as the app extracts it on device, column
// tabs included, so parsers can be checked against real PDFs:
//
//   tool/pdf_text/extract.sh ~/Documents/Recipes /tmp/menu-kit-text
//   MENU_KIT_TEXT_DIR=/tmp/menu-kit-text flutter test test/shopping/menu_kit_real_pdf_test.dart
//
// Keep the column rules in step with ColumnTextStripper.kt.
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.text.TextPosition;
import java.io.*;
import java.util.*;
public class ColumnTextExtract {
  static class S extends PDFTextStripper {
    float lastEnd = Float.NaN; boolean pending = false; List<Float> starts = new ArrayList<>();
    S() throws IOException { super(); }
    @Override protected void startPage(PDPage p) throws IOException { starts.clear(); super.startPage(p); }
    boolean known(float x) { for (float s : starts) if (Math.abs(s - x) < 2.5f) return true; return false; }
    void remember(float x) { if (!known(x)) starts.add(x); }
    static float limit(TextPosition p) { return Math.max(4 * p.getWidthOfSpace(), 12f); }
    @Override protected void writeWordSeparator() { pending = true; }
    @Override protected void writeString(String text, List<TextPosition> pos) throws IOException {
      if (pos.isEmpty()) { super.writeString(text, pos); return; }
      StringBuilder glyphs = new StringBuilder();
      for (TextPosition p : pos) glyphs.append(p.getUnicode());
      boolean mapped = glyphs.toString().equals(text);
      TextPosition first = pos.get(0);
      if (pending) {
        float gap = Float.isNaN(lastEnd) ? 0 : first.getXDirAdj() - lastEnd;
        boolean column = gap > limit(first) || (gap > 0 && known(first.getXDirAdj()));
        if (column) remember(first.getXDirAdj());
        output.write(column ? "\t" : getWordSeparator());
        pending = false;
      } else if (Float.isNaN(lastEnd) && first.getXDirAdj() > first.getPageWidth() * 0.45f) {
        output.write("\t"); remember(first.getXDirAdj());
      }
      if (!mapped) { super.writeString(text, pos); }
      else {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < pos.size(); i++) {
          TextPosition p = pos.get(i);
          if (i > 0) {
            TextPosition prev = pos.get(i - 1);
            float x = p.getXDirAdj();
            float gap = x - (prev.getXDirAdj() + prev.getWidthDirAdj());
            boolean afterSpace = prev.getUnicode().equals(" ");
            if (!p.getUnicode().equals(" ") && (gap > limit(p) || (afterSpace && known(x)))) {
              if (afterSpace) out.setLength(out.length() - 1);
              out.append('\t'); remember(x);
            }
          }
          out.append(p.getUnicode());
        }
        output.write(out.toString());
      }
      TextPosition l = pos.get(pos.size() - 1); lastEnd = l.getXDirAdj() + l.getWidthDirAdj();
    }
    @Override protected void writeLineSeparator() throws IOException { pending = false; lastEnd = Float.NaN; super.writeLineSeparator(); }
  }
  public static void main(String[] a) throws Exception {
    try (PDDocument d = PDDocument.load(new File(a[0]))) { S s = new S(); s.setSortByPosition(true); System.out.print(s.getText(d)); }
  }
}
