#autoload run script

if [[ -f ~/warkopv.sh ]] && [[ -z "$WARKOP_RUN" ]]; th>
    export WARKOP_RUN=1
    ~/warkop.sh
    unset WARKOP_RUN
fi
