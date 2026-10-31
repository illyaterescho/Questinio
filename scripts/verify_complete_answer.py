import json, time, urllib.request
from pathlib import Path
prompt = 'Відповідай українською як досвідчений розробник колезі. Використовуй природні терміни: таска, тред, рантайм, проміс, колбек. Не плутай concurrency та parallelism. Код fenced Markdown, формули LaTeX.'
question = 'Поясни async/await у JavaScript, event loop, microtasks і чому async не означає паралельний тред. Дай мінімальний приклад з очікуваним порядком логів, типові помилки і формулу закону Амдала у LaTeX. Напиши повну відповідь приблизно на 450 слів, завершивши код і висновок.'
for model in ['qwen3.5:9b']:
    request = urllib.request.Request('http://127.0.0.1:11434/api/chat', data=json.dumps({'model':model,'messages':[{'role':'system','content':prompt},{'role':'user','content':question}],'stream':True,'think':False,'keep_alive':'2m','options':{'num_predict':-1,'num_ctx':8192,'temperature':0.3}}).encode(), headers={'Content-Type':'application/json'})
    start=time.monotonic(); first=None; answer=''; final={}
    with urllib.request.urlopen(request,timeout=180) as response:
        for line in response:
            packet=json.loads(line); token=packet.get('message',{}).get('content','')
            if token and first is None:first=time.monotonic()-start
            answer+=token
            if packet.get('done'):final=packet;break
    result={'model':model,'first_token':first,'total':time.monotonic()-start,'eval_count':final.get('eval_count'),'done_reason':final.get('done_reason'),'answer':answer}
    Path('verification-complete-'+model.replace(':', '-')+'.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print({k:v for k,v in result.items() if k!='answer'},flush=True)
