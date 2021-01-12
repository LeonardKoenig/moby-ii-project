#! /bin/sh

set -eu
#set -x

# Downloads the original .zip files of the
# Moby Project (https://en.wikipedia.org/wiki/Moby_Project) hosted at
# Project Gutenberg.
download() {
    trunk=https://www.gutenberg.org/files/

    p=$1
    i=$2
    release=$3

    name=${p#*:}
    id=${p%:*}
    filename=${i}m${id}10.zip
    curl -o "$filename" $trunk/"$release"/old/"$filename"
}

# Extracts the sources into */src subdirectories.
extract() {
    p=$1
    i=$2

    name=${p#*:}
    id=${p%:*}
    filename=${i}m${id}10.zip
    mkdir -p "$name"
    unzip -o -d "$name"/src "$filename"
}

# Converts files to UTF-8 as some are in DOS Codepages, i.e. non-iso extended-ASCII
# Also use UNIX line terminators
postprocess() {
    p=$1
    name=${p#*:}
    cd "$name"/src

    # Split the Gutenberg header, legal text and actual readme
    readme=$(find . \( -type f -a -iname 'aareadme.txt' \) -printf '%f\n')

    lines=$(wc -l "$readme" | cut -f1 -d' ')
    legal_start=$(grep -n 'The Legal Small Print' "$readme" | cut -f1 -d:)
    legal_end=$(grep -n 'END THE SMALL PRINT!' "$readme" | cut -f1 -d:)

    # Before the legal text we have a common header by the Gutenberg Project
    head -n $((legal_start-2)) "$readme" > ../gutenberg.txt
    # It is followed by a Legal Small Print
    head -n "$legal_end" "$readme" | tail -n -$((legal_end-legal_start+1)) > ../legal.txt
    # Finally, we have the original Moby Project Documentation
    tail -n -$((lines-legal_end-4)) "$readme" > ../readme.txt.tmp
    # Which is, however, followed by a trailer of the Gutenberg Project
    tail -n -3 ../readme.txt.tmp >> ../gutenberg.txt
    head -n $((lines-legal_end-8)) ../readme.txt.tmp > ../readme.txt
    rm ../readme.txt.tmp

    # The pronounciator also has an original readme from CMU
    if [ "$name" = pronunciator ]; then
        cp abreadme.txt ../README_cmu.txt
    fi

    tmpfiles=
    files=$(find . \( -type f -a -not -iname '*readme.txt' \) -printf '%f\n')
    for f in $files; do
        # Default encoding
        encoding=ASCII
        # Files to be deleted later

        new=$(echo "$f" | tr '[:upper:]' '[:lower:]')
        case $f in
        mhyph.txt)
            # Hyphens are coded using 0xA5 which isn't in ASCII.  Convert it
            # to TeX Hyphenation patterns using \-
            sed 's/\xA5/\\-/g' "$f" > ../"$f".tmp

            # Now redirect the convert command to this temporary file and
            # append the new temporary file to the files to be deleted
            # later.
            f=../$f.tmp
            tmpfiles="$tmpfiles $f"

            # Examples *only* decoded in selected encoding marked with *
            #   mhyph:92: ab\-bé
            #   mhyph:93: ab\-bés
            # * mhyph.txt:1821: Ae\-ë\-tes
            encoding=MAC
            ;;
        german.txt|USACONST.TXT|NAMES.TXT)
            # NAMES.TXT:820: Amélie
            # german.txt:1959: André
            # USACONST.TXT:196: ─
            encoding=CP850
            ;;
        japanese.txt)
            #TODO
            # Completely unknown encoding, especially the case below seems
            # to be completely invalid/broken(?)
            # japanese.txt:40195 kansei???
            encoding=""
            ;;
        mobypos.txt|mpron.txt)
            # Examples *only* decoded in selected encoding marked with *
            #   mobypos.txt:807: Abélard
            # * mobypos.txt:845: Académie Française
            #   mpron.txt:10712: Auguste Édouard
            #   mpron.txt:15569: Belaúnde
            #   mpron.txt:16927: Bidú
            # * mpron.txt:17758: Bissão
            # Original readme states for mobypos.txt that é is encoded as
            # 0x8E which also matches the Mac OS Roman coding.
            encoding=MAC
            ;;
        COMPOUND.TXT)
            # Unknown or various different encodings(?)
            # Remove the following lines/words:
            # * 4573: Amélie
            # * 73293: PoP
            # * 73294: PoP
            # * 100109: ambit piousness
            # * 183280: no one nobody
            # * 193597: play d
            # * 246886: villain dé
            sed '4573d;73293d;73294d;100109d;183280d;193597d;246886d;' \
                "$f" > ../"$f".tmp

            # cf. mhyph.txt
            f=../$f.tmp
            tmpfiles="$tmpfiles $f"
            ;;
        esac

        if [ -n "$encoding" ]; then
            error=0
            printf "Decoding %s from %s\n" "$f" $encoding >&2
            iconv -f $encoding -t utf-8 "$f" > ../"$new" || error=$?
            if [ $error -ne 0 ]; then
                printf 'Error postprocessing %s\n' "$name"/src/"$f" >&2
                exit 1
            fi
        else
            printf "Skipping %s\n" "$f" >&2
        fi
    done
    # Deleting temporary files
    for del in $tmpfiles; do
        rm -fv "$del"
    done
    cd - >/dev/null
}


# Entry
help='Downloads & Processes the Moby Project files

  -d\tDownload original ZIPs
  -e\tExtract downloaded files
  -p\tPostprocess them into UTF-8 coded usable lists\n'

projects="word:words \
          thes:thesaurus \
          posp:part-of-speech \
          hyph:hyphenator \
          pron:pronunciator \
          lang:language"

if [ $# -eq 0 ]; then
    printf "Usage: %s <Options>\n$help" "$0" >&2
    exit 1
fi
while getopts deph opt; do
    dflag=
    eflag=
    pflag=
    case $opt in
    d)  dflag=1
        ;;
    e)  eflag=1
        ;;
    p)  pflag=1
        ;;
    h)  printf "Usage: %s <Options>\n$help" "$0"
        exit 0
        ;;
    ?)  printf "Usage: %s <Options>\n$help" "$0" >&2
        exit 1
        ;;
    esac

    i=1
    release=3201
    for p in $projects; do
        if [ -n "$dflag" ]; then
            download "$p" $i $release
        fi
        if [ -n "$eflag" ]; then
            extract "$p" $i
        fi
        if [ -n "$pflag" ]; then
            postprocess "$p"
        fi

        i=$((i+1))
        release=$((release+1))
    done
done
shift $((OPTIND -1))
#args=$*
