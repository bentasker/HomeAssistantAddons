#!/usr/bin/with-contenv bashio

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
            bashio::log.info "Changes detected - overwriting DNS Config"
            make_and_push
        fi
    else
        # We don't have a copy of the last change
        make_and_push
    fi
}


# bashio uses set -e by default, we do not want that
# we're specifically testing things that may fail
set +e

# Catch an easy oversight
FAIL=0
docker ps 2>&1 >/dev/null
if [ ! "$?" == "0" ]
then
    bashio::log.error "Unable to access docker"
    bashio::log.error "Did you forget to disable protection mode?"
    FAIL=1
    # We don't exit here, because supervisor would only restart us
fi


while true
do
    if [ "$FAIL" == "0" ]
    then
        fetch_and_check
    fi
    sleep $INTERVAL
done
