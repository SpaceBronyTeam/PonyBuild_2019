var/datum/censure_global/Censure
/client/var/censure = 1

datum/censure_global
	var/list/ids = list() //"" = ""

	New()
		LoadIDFromData() // 2 - Сначала записываются фразы из файла этой локализации

	proc/LoadIDFromData()
		var/text = file2text("data/censure.txt")

		//Дальше нужно поделить на части
		while(findtext(text, "\"") && findtext(text, "="))
			var/first_pos = findtext(text, "\"")+1

			var/l1 = copytext(text, first_pos, findtext(text, "\"", first_pos))//Исправить начальную позицию

			text = copytext(text, findtext(text, "=")+1)

			first_pos = findtext(text, "\"")+1
			var/l2 = copytext(text, first_pos, findtext(text, "\"", first_pos))

			ids[l1] = l2

			text = copytext(text, findtext(text, "\"", 2) + min(2, lentext(text)-findtext(text, "\"", 2)) )





/world/New()
	..()
	Censure = new()


proc/pony_censure(var/phrase)
	for(var/cens_text in Censure.ids)
		if(!cens_text || cens_text == "")
			continue
		if(!Censure.ids[cens_text] || Censure.ids[cens_text] == "")//Если запись пуста, то возвращаем обычное значение
			continue
		if(findtext(cens_text, phrase))
			phrase = replacetext(phrase, cens_text, Censure.ids[cens_text])//Иначе цензурный вариант
	return phrase