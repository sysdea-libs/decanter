defmodule ConnectionNegotiatorTest do
  use ExUnit.Case
  require Decanter.ConnectionNegotiator, as: ConNeg

  def test_neg(mode, table) do
    for {input, accepts, expected} <- table do
      assert ConNeg.find_best(mode, input, accepts) == expected
    end
  end

  test "accept" do
    test_neg(:accept,
             [{"text/html", ["text/html", "application/json"], "text/html"},
              {"text/*", ["text/html", "application/json"], "text/html"},
              {"text/html", ["*/*"], "text/html"},
              {"text/html;q=0.5,application/json", ["*/*"], "application/json"},
              {"text/*", ["*/*"], nil},
              {"a/b/c", ["text/html"], nil},
              {"*/*", ["*/*"], nil},
              {"*/*", ["*/*", "text/html"], "text/html"},
              {"*/*", ["text/html", "application/json"], "text/html"},
              {"text/html", ["text/*", "application/json"], "text/html"},
              {"application/json", ["text/html", "application/json"], "application/json"}])
  end

  test "charset" do
    test_neg(:charset,
      [ {"iso-8859-5, unicode-1-1;q=0.8", ["iso-8859-5", "unicode-1-1"], "iso-8859-5"},
        {"iso-8859-15;q=1, utf-8;q=0.8, utf-16;q=0.6, iso-8859-1;q=0.8", ["iso-8859-15", "utf-16"],  "iso-8859-15"},

        # iso-8859-1 gets the highest score because there is no * so it gets a quality value of 1
        {"iso-8859-15;q=0.6, utf-16;q=0.9", ["iso-8859-1", "iso-8859-15", "utf-16"], "iso-8859-1"},

        # utf-16 gets the highest score because there is no * but iso-8859-1 is mentioned at a lower score
        {"iso-8859-15;q=0.6, utf-16;q=0.9, iso-8859-1;q=0.1", ["iso-8859-1", "iso-8859-15", "utf-16"], "utf-16"},
        {"iso-8859-15;q=0.6, *;q=0.8, utf-16;q=0.9", ["iso-8859-15", "utf-16"], "utf-16"},

        # ASCII should be returned because it matches *, which gives it a 0.8 score, higher than iso-8859-15
        {"iso-8859-15;q=0.6, *;q=0.8, utf-16;q=0.9", ["iso-8859-15", "ASCII"], "ascii"},

        # iso-8859-1 is always available unless score set to 0
        {"ascii;q=0.5", ["ascii", "ISO-8859-1"], "iso-8859-1"},

        # bad q values default to 1.0
        {"ascii;q=f", ["ascii", "ISO-8859-1"], "ascii"},

        # Nothing is returned because ASCII is gets a score of 0
        {"iso-8859-15;q=0.6, utf-16;q=0.9", ["ASCII"], nil},

        # test some exotic formatting variants, not complete, though.
        {"iso-8859-15,\r\nASCII", ["ASCII"], "ascii"},

        # charset must be compared case insensitively
        {"ASCII", ["ascii"], "ascii"} ])
  end

  test "encoding" do
    test_neg(:encoding,
      [ {"compress;q=0.4, gzip;q=0.2",           ["compress", "gzip"], "compress"},
        {"compress;q=0.4, gzip;q=0.2",           ["identity"],         "identity"},
        {"compress;q=0.4, gzip;q=0.8",           ["compress", "gzip"], "gzip"},
        {"identity, compress;q=0.4, gzip;q=0.8", ["compress", "gzip"], "identity"},
        {"compress",                             ["gzip"],             "identity"},
        {"identity",                             ["gzip"],             "identity"},
        {"identity;q=0, bzip;q=0.1",             ["gzip"],             nil},
        {"*;q=0, bzip;q=0.1",                    ["gzip"],             nil},
        {"*;q=0, identity;q=0.1",                ["gzip"],             "identity"} ])
  end

  test "language" do
    test_neg(:language,
      [ {"da, en-gb;q=0.8, en;q=0.7", ["da", "en-gb", "en"], "da"},
        {"da, en-gb;q=0.8, en;q=0.7", ["en-gb", "en"], "en-gb"},
        {"da, en-gb;q=0.8, en;q=0.7", ["en"], "en"},
        {"da, en-gb;q=0.8", ["en-cockney"], nil},
        {"da, en-gb;q=0.8, en;q=0.7", ["en-cockney"], "en-cockney"},
        {"DA", ["dA"], "da"} ])

      # TODO: multi-language accepts
  end

end
