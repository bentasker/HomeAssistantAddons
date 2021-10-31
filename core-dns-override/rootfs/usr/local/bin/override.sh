#!/usr/bin/with-contenv bashio

#CONTAINER_NAME=hassio_dns
#INTERVAL=60

CONFIG_PATH=/data/options.json

function make_and_push(){

    MODE=$1

    if [ "$MODE" == "last" ]
    then
        # Strip direction to the fallback
        #
        # Also, turn off health checks - it's unneeded traffic, this isn't a kubernetes cluster
        cat current | sed 's~dns://127.0.0.1:5553~~g' | sed 's~fallback REFUSED.*~~g' | sed 's~health_check .*~~' > new
        docker cp new $CONTAINER_NAME:/etc/corefile
        
        # take a copy as our "last"
        mv new last
    else
        docker cp $MODE $CONTAINER_NAME:/etc/corefile
    fi
    # Now restart coredns
    docker exec $CONTAINER_NAME pkill coredns
}

function fetch_and_check(){
    docker cp $CONTAINER_NAME:/etc/corefile ./current
    
    if [ "$USE_TEMPLATE" == "true" ]
    then
        COMP_FILE="/config/dns-override-template"
        if [ ! -f "$COMP_FILE" ]
        then
            bashio::log.error "/config/dns-override-template does not exist - will patch existing file instead"
            COMP_FILE="last"
        fi
    else
        COMP_FILE="last"
    fi
    
    if [ -f $COMP_FILE ]
    then
        diff -s current $COMP_FILE > /dev/null
        if [ ! "$?" == "0" ]
        then
            # Files differ
            bashio::log.info "Changes detected - overwriting DNS Config"
            make_and_push $COMP_FILE
        fi
    else
        # We don't have a copy of the last change
        make_and_push $COMP_FILE
    fi

    # Tidy up
    rm current
}

function check_supervisor_dns(){
    # Prevent Supervisor from auto-updating
    #
    # https://github.com/bentasker/HomeAssistantAddons/issues/1
    #

    SUPERVISOR=`bashio::config supervisor_container`
    UPDATE_DOMAIN=`bashio::config block_domain`
    BLOCK_IP=`bashio::config block_dest`
    
    # Copy down /etc/hosts
    docker cp $SUPERVISOR:/etc/hosts ./hosts
    
    if [ `bashio::config block_supervisor_updates` == "false" ]
    then
        # Ensure that it's not configured
        grep -E "^([0-9,\.]+)[[:space:]]+$UPDATE_DOMAIN" hosts 2>&1 >/dev/null
        if [ "$?" == "0" ]
        then    
            bashio::log.info "Removing update block from Supervisor /etc/hosts"
            grep -v -E "^([0-9,\.]+)[[:space:]]+$UPDATE_DOMAIN" hosts > hosts_new
            
            # We have to take the long way round
            #
            # Can't copy direct - docker borks because the file's in use
            # and can't grep from /etc/hosts direct into itself, as we'll end up
            # with an empty file
            docker cp hosts_new $SUPERVISOR:/etc/hosts.tmp
            docker exec hassio_supervisor bash -c "cat /etc/hosts.tmp > /etc/hosts"
            docker exec hassio_supervisor bash -c "rm -f /etc/hosts.tmp"
            rm hosts_new
        fi
        rm hosts
        return
    fi
    
    grep -E "^([0-9,\.]+) $UPDATE_DOMAIN\$" hosts 2>&1 >/dev/null
    if [ ! "$?" == "0" ]
    then
        # Update it
        bashio::log.info "Changes detected - overwriting Supervisor /etc/hosts"
        docker exec hassio_supervisor bash -c "echo '$BLOCK_IP    $UPDATE_DOMAIN' | tee -a /etc/hosts" 
        # Docker won't let us do this:
        #docker cp hosts $SUPERVISOR:/etc/hosts
    fi
    rm hosts
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

# Get config
INTERVAL="`bashio::config 'interval'`"
CONTAINER_NAME=`bashio::config dns_container`
USE_TEMPLATE=`bashio::config use_dns_template`

bashio::log.info "Launched"
while true
do
    if [ "$FAIL" == "0" ]
    then
        fetch_and_check
        check_supervisor_dns
    else
        bashio::log.error "Did you forget to disable protection mode?"    
    fi
    sleep $INTERVAL
done
