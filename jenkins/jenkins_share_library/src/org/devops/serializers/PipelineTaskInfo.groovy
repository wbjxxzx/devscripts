package org.devops.serializers

class PipelineTaskInfo implements Serializable {
    private props = [:]

    PipelineTaskInfo put(String key, value) {
        props.put(key, value)
        return this
    }

    def get(String key){
        return props.get(key)
    }
}
