#!/bin/sh

CONTAINER_NAME=hassio_dns
INTERVAL=60

function make_and_push(){
    # Strip direction to the fallback
    #
    # Also, turn off health checks - it's unneeded traffic, this isn't a kubernetes cluster
    cat current | sed 's~dns://127.0.0.1:5553~~g' | sed 's~fallback REFUSED.*~~g' | sed 's~health_check .*~~' > new
    docker cp new $CONTAINER_NAME:/etc/corefile
    
    # take a copy as our "last"
    mv new last
    rm current
    
    # Now restart coredns
    docker exec $CONTAINER_NAME pkill coredns
}

function fetch_and_check(){
    docker cp $CONTAINER_NAME:/etc/corefile ./current
    if [ -f last ]
    then
        diff -s current last > /dev/null
        if [ ! "$?" == "0" ]
        then
            # Files differ
            make_and_push
        fi
    else
        # We don't have a copy of the last change
        make_and_push
    fi
}


while true
do
    fetch_and_check
    sleep $INTERVAL
done
